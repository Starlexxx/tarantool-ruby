# frozen_string_literal: true

RSpec.describe Tarantool::Client::Transport::Link do
  let(:server) { FakeTarantool.new { |request, fake| fake.reply(request, [request.type]) } }
  let(:options) { {} }
  let(:callbacks) { Thread::Queue.new }
  let(:on_connect) { ->(connection) { callbacks << [:connect, connection] } }
  let(:backoff) { nil }

  def config
    Tarantool::Client::Configuration.build(
      server.uri, reconnect_delay: 0.01, reconnect_max_delay: 0.02, connect_timeout: 0.5, **options
    )
  end

  def build_link
    described_class.new(config, on_connect:, on_ready: ->(connection) { callbacks << [:ready, connection] }, backoff:)
  end

  def ping = Tarantool::Client::Protocol::Requests::Ping.new

  describe 'the first connection' do
    after { server.stop }

    it 'raises from connect and starts no reconnect thread' do
      server.refusing = true

      expect { build_link.connect }.to raise_error(Tarantool::ConnectionError, /cannot connect/)
      expect(Thread.list.none? { |thread| thread.name&.start_with?('tarantool-reconnect') }).to be(true)
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

    it 'reconnects after the server drops the connection' do
      drop_connection

      expect(link.perform(ping, timeout: 1).data).to eq([0x40])
      expect(server.connections).to eq(2)
    end

    it 'runs on_connect and then on_ready for every new connection' do
      drop_connection
      link.perform(ping, timeout: 1)

      events = Array.new(4) { callbacks.pop(timeout: 1) }
      expect(events.map(&:first)).to eq(%i[connect ready connect ready])
      expect(events.map(&:last).uniq.size).to eq(2)
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
      expect(Tarantool::Client::Transport::Deadline.now - started).to be_between(0.4, 1)
    end

    it 'bounds the wait for a reconnect by the request timeout' do
      take_down
      started = Tarantool::Client::Transport::Deadline.now

      expect { link.perform(ping, timeout: 0.05) }.to raise_error(Tarantool::ConnectionError, /not connected/)
      expect(Tarantool::Client::Transport::Deadline.now - started).to be < 0.3
    end

    it 'stops reconnecting on close' do
      take_down
      link.close

      expect(Thread.list.none? { |thread| thread.name&.start_with?('tarantool-reconnect') && thread.alive? })
        .to be(true)
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
end
