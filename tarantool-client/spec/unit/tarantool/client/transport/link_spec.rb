# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe Tarantool::Client::Transport::Link do
  let(:server) { FakeTarantool.new { |request, fake| fake.reply(request, [request.type]) } }
  let(:options) { {} }
  let(:callbacks) { Thread::Queue.new }
  let(:on_connect) { ->(connection) { callbacks << [:connect, connection] } }

  def on_ready = ->(connection) { callbacks << [:ready, connection] }
  def on_lost = -> { callbacks << [:lost] }
  def backoff = nil

  def config
    Tarantool::Client::Configuration.build(
      server.uri, reconnect_delay: 0.01, reconnect_max_delay: 0.02, connect_timeout: 0.5, **options
    )
  end

  def build_link
    described_class.new(config, on_connect:, on_ready:, on_lost:, backoff:)
  end

  def alive_threads(prefix) = Thread.list.select { |thread| thread.alive? && thread.name&.start_with?(prefix) }

  def ping = Tarantool::Client::Protocol::Requests::Ping.new

  describe 'the first connection' do
    after { server.stop }

    it 'raises from connect and starts no reconnect thread' do
      server.refusing = true

      expect { build_link.connect }.to raise_error(Tarantool::ConnectionError, /cannot connect/)
      expect(alive_threads('tarantool-reconnect')).to be_empty
    end

    context 'when on_ready fails' do
      let(:on_ready) { ->(_connection) { raise ArgumentError, 'ready' } }

      it 'closes the connection and raises' do
        expect { build_link.connect }.to raise_error(ArgumentError, 'ready')
        expect(alive_threads('tarantool-reader')).to be_empty
      end
    end
  end

  describe 'a connected link' do
    subject(:link) { build_link.connect }

    after do
      link.close
      server.stop
    end

    def drop_connection
      dropped = link.connection
      server.disconnect

      wait_for { dropped.closed? }
    end

    def take_down
      link
      server.refusing = true

      drop_connection
    end

    it 'performs requests on the connection' do
      expect(link.perform(ping, timeout: 1).data).to eq([0x40])
    end

    it 'is connected until the connection is lost' do
      expect(link.connected?).to be(true)
      take_down
      expect(link.connected?).to be(false)
    end

    it 'reconnects after the server drops the connection' do
      drop_connection

      expect(link.perform(ping, timeout: 1).data).to eq([0x40])
      expect(server.connections).to eq(2)
    end

    it 'runs on_connect and then on_ready for every new connection' do
      drop_connection
      link.perform(ping, timeout: 1)

      events = Array.new(5) { callbacks.pop(timeout: 1) }.reject { |event| event == [:lost] }
      expect(events.map(&:first)).to eq(%i[connect ready connect ready])
      expect(events.map(&:last).uniq.size).to eq(2)
    end

    it 'runs on_lost once a reconnect starts, before its first attempt' do
      drop_connection
      link.perform(ping, timeout: 1)

      expect(Array.new(5) { callbacks.pop(timeout: 1).first }).to eq(%i[connect ready lost connect ready])
    end

    context 'when on_lost fails' do
      def on_lost = -> { raise ArgumentError, 'lost' }

      it 'reconnects anyway and reports the error' do
        warnings = Thread::Queue.new
        allow(Warning).to receive(:warn) { |message, **| warnings << message }
        drop_connection

        expect(warnings.pop(timeout: 1)).to include('on_lost failed')
        expect(link.perform(ping, timeout: 1).data).to eq([0x40])
      end
    end

    context 'when on_connect fails once after the drop' do
      let(:on_connect) do
        calls = 0
        ->(_connection) { raise Tarantool::ConnectionError, 'schema' if (calls += 1) == 2 }
      end

      it 'retries the attempt' do
        drop_connection

        expect(link.perform(ping, timeout: 1).data).to eq([0x40])
        expect(server.connections).to eq(3)
      end
    end

    context 'when on_ready fails after the drop' do
      let(:on_ready) do
        calls = 0
        ->(_connection) { raise ArgumentError, 'ready' if (calls += 1) == 2 }
      end

      it 'keeps the new connection and reports the error' do
        warnings = Thread::Queue.new
        allow(Warning).to receive(:warn) { |message, **| warnings << message }
        drop_connection

        expect(warnings.pop(timeout: 1)).to include('ready')
        expect(link.perform(ping, timeout: 1).data).to eq([0x40])
        expect { link.close }.not_to raise_error
      end
    end

    context 'when the reconnect thread hits an unexpected error' do
      let(:backoff) { instance_double(Tarantool::Client::Backoff) }

      before { allow(backoff).to receive(:delay).and_raise(RuntimeError, 'bug') }

      it 'closes the link with the error' do
        allow(Warning).to receive(:warn)
        drop_connection

        expect { link.perform(ping, timeout: 1) }
          .to raise_error(Tarantool::ConnectionError, /reconnect to .* failed: RuntimeError: bug/)
      end
    end

    context 'when Thread.new raises ThreadError on the reconnect' do
      let(:raise_flag) { [false] }

      before do
        allow(Thread).to receive(:new).and_wrap_original do |original, &block|
          raise ThreadError, "can't alloc thread" if raise_flag[0]

          original.call(&block)
        end
      end

      it 'gives up with ConnectionError instead of waiting for a timeout' do
        link
        raise_flag[0] = true
        drop_connection

        expect { link.perform(ping, timeout: 5) }.to raise_error(Tarantool::ConnectionError, /cannot reconnect/)
        expect(link.connected?).to be(false)
      end
    end

    context 'when on_connect waits for a reply on the new connection' do
      let(:server) { FakeTarantool.new }
      let(:options) { { connect_timeout: 2 } }
      let(:on_connect) do
        calls = 0
        ->(connection) { connection.perform(ping, timeout: 2) if (calls += 1) == 2 }
      end

      it 'cuts the attempt short on close' do
        drop_connection
        server.next_request
        started = Tarantool::Client::Transport::Deadline.now
        link.close

        expect(Tarantool::Client::Transport::Deadline.now - started).to be < 0.5
      end
    end

    context 'with a named user' do
      let(:options) { { user: 'app', password: 'secret' } }

      it 'keeps retrying while the server rejects the credentials' do
        link
        server.auth_error = 'User not found or supplied credentials are invalid'
        drop_connection
        wait_for { server.connections >= 3 }
        server.auth_error = nil

        expect(link.perform(ping, timeout: 1).data).to eq([0x40])
      end
    end

    it 'fails a request made while reconnecting after connect_timeout' do
      take_down
      started = Tarantool::Client::Transport::Deadline.now

      expect { link.perform(ping, timeout: 5) }.to raise_error(Tarantool::ConnectionError, /not connected/)
      expect(Tarantool::Client::Transport::Deadline.now - started).to be_between(0.4, 2)
    end

    it 'bounds the wait for a reconnect by the request timeout' do
      take_down
      started = Tarantool::Client::Transport::Deadline.now

      expect { link.perform(ping, timeout: 0.05) }.to raise_error(Tarantool::ConnectionError, /not connected/)
      expect(Tarantool::Client::Transport::Deadline.now - started).to be < 0.3
    end

    it 'bounds the wait for a connection by the given deadline' do
      take_down
      started = Tarantool::Client::Transport::Deadline.now

      expect { link.connection(Tarantool::Client::Transport::Deadline.after(0.05)) }
        .to raise_error(Tarantool::ConnectionError, /not connected/)
      expect(Tarantool::Client::Transport::Deadline.now - started).to be < 0.3
    end

    it 'stops reconnecting on close' do
      take_down
      link.close

      expect(alive_threads('tarantool-reconnect')).to be_empty
    end

    it 'raises ClientClosedError after close' do
      link.close

      expect { link.perform(ping, timeout: 1) }.to raise_error(Tarantool::ClientClosedError)
    end

    context 'with limited attempts' do
      let(:options) { { reconnect_attempts: 3 } }
      let(:backoff) { instance_double(Tarantool::Client::Backoff, delay: 0.01) }

      it 'gives up after reconnect_attempts and closes' do
        take_down

        expect { link.perform(ping, timeout: 1) }
          .to raise_error(Tarantool::ConnectionError, /cannot reconnect to .* after 3 attempts/)
        expect(backoff).to have_received(:delay).exactly(3).times
        expect(backoff).to have_received(:delay).with(2)
      end
    end

    context 'without reconnect' do
      let(:options) { { reconnect: false } }

      it 'keeps the dead connection and does not reconnect' do
        drop_connection

        expect { link.perform(ping, timeout: 1) }.to raise_error(Tarantool::ConnectionError, /lost/)
        expect(server.connections).to eq(1)
      end
    end
  end

  describe 'process exit without close' do
    it 'prints nothing to stderr when a connected client is not closed before exit' do
      srv = FakeTarantool.new { |request, fake| fake.reply(request, []) }
      lib = File.expand_path('../../../../../lib', __dir__)
      script = "require 'tarantool/client'; Tarantool::Client.new('unix:#{srv.path}'); sleep 0.05"

      _out, stderr, _status = Open3.capture3(RbConfig.ruby, '-I', lib, '-e', script)

      expect(stderr).to be_empty
    ensure
      srv&.stop
    end
  end
end
