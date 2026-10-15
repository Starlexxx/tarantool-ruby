# frozen_string_literal: true

require 'timeout'

RSpec.describe Tarantool::Client::Transport::Connection do
  let(:handler) { nil }
  let(:server) { FakeTarantool.new(&handler) }
  let(:config) { Tarantool::Client::Configuration.build(server.uri, user: 'app', password: 'secret') }
  let(:connection) { described_class.new(config).connect }

  def eval_request(expression)
    Tarantool::Client::Protocol::Requests::Eval.new(expression:, arguments: [])
  end

  after { server.stop }

  describe '#connect' do
    after { connection.close }

    it 'reads the server version from the greeting' do
      expect(connection.greeting.version).to eq('2.11.1')
    end

    it 'stores features announced by the server' do
      expect(connection.server_features).to eq([0, 1, 2, 3])
    end

    it 'authenticates a named user' do
      connection

      expect(server.auth_requests).to eq(1)
    end

    context 'without a user' do
      let(:config) { Tarantool::Client::Configuration.build(server.uri) }

      it 'skips authentication' do
        connection

        expect(server.auth_requests).to eq(0)
      end
    end
  end

  describe 'connect failures' do
    it 'raises AuthenticationError when credentials are rejected' do
      rejecting = FakeTarantool.new(auth_error: 'User not found or supplied credentials are invalid')
      config = Tarantool::Client::Configuration.build(rejecting.uri, user: 'app', password: 'wrong')

      expect { described_class.new(config).connect }.to raise_error(Tarantool::AuthenticationError, /credentials/)
    ensure
      rejecting.stop
    end

    it 'keeps the server error code and the server error as cause' do
      rejecting = FakeTarantool.new(auth_error: 'User not found or supplied credentials are invalid')
      config = Tarantool::Client::Configuration.build(rejecting.uri, user: 'app', password: 'wrong')

      expect { described_class.new(config).connect }.to raise_error(Tarantool::AuthenticationError) { |error|
        expect([error.code, error.cause]).to match([47, an_instance_of(Tarantool::ServerError)])
      }
    ensure
      rejecting.stop
    end

    it 'raises ConnectionError when the server sends no greeting' do
      silent = FakeTarantool.new(greeting: false)
      config = Tarantool::Client::Configuration.build(silent.uri, connect_timeout: 0.1)

      expect { described_class.new(config).connect }.to raise_error(Tarantool::ConnectionError, /cannot connect/)
    ensure
      silent.stop
    end

    it 'raises ConnectionError when the server rejects the handshake' do
      rejecting = FakeTarantool.new(id_error: 'Unknown request type')
      config = Tarantool::Client::Configuration.build(rejecting.uri)

      expect { described_class.new(config).connect }
        .to raise_error(Tarantool::ConnectionError, /cannot connect.*Unknown request type/)
    ensure
      rejecting.stop
    end

    it 'bounds the whole handshake by one connect timeout' do
      slow = FakeTarantool.new(delay: 0.15)
      config = Tarantool::Client::Configuration.build(slow.uri, user: 'app', password: 'secret', connect_timeout: 0.25)

      expect { described_class.new(config).connect }.to raise_error(Tarantool::ConnectionError, /cannot connect/)
    ensure
      slow.stop
    end

    it 'raises ConnectionError when nothing listens' do
      config = Tarantool::Client::Configuration.build('unix:/nonexistent/tarantool.sock')

      expect { described_class.new(config).connect }.to raise_error(Tarantool::ConnectionError, /nonexistent/)
    end
  end

  describe '#perform' do
    after { connection.close }

    context 'when the server answers' do
      let(:handler) { ->(request, fake) { fake.reply(request, [request.body[0x27]]) } }

      it 'returns the response' do
        expect(connection.perform(eval_request('return 1'), timeout: 1).data).to eq(['return 1'])
      end

      it 'stays usable when a write times out before sending anything' do
        writer = connection.instance_variable_get(:@writer)
        allow(writer).to receive(:write).and_raise(Tarantool::TimeoutError, 'socket write timed out')

        expect { connection.perform(eval_request('x'), timeout: 0.2) }.to raise_error(Tarantool::TimeoutError)
        allow(writer).to receive(:write).and_call_original
        expect(connection.perform(eval_request('return 1'), timeout: 1).data).to eq(['return 1'])
      end

      it 'reports a write lock held past the timeout as no response' do
        lock = connection.instance_variable_get(:@writer).instance_variable_get(:@lock)
        held = Thread::Queue.new
        release = Thread::Queue.new
        holder = Thread.new { lock.synchronize(nil) { (held << true) && release.pop } }
        held.pop

        expect { connection.perform(eval_request('x'), timeout: 0.05) }
          .to raise_error(Tarantool::TimeoutError, 'no response within 0.05s')
      ensure
        release << true
        holder.join
      end

      it 'sends the schema version in the request header' do
        connection.perform(eval_request('return 1'), timeout: 1, schema_version: 80)

        expect(server.headers.last[0x05]).to eq(80)
      end

      it 'raises TimeoutError without sending when no time is left' do
        connection
        sent = server.headers.size

        expect { connection.perform(eval_request('x'), timeout: 0) }.to raise_error(Tarantool::TimeoutError)
        connection.perform(eval_request('return 1'), timeout: 1)
        expect(server.headers.size).to eq(sent + 1)
      end
    end

    context 'when the server returns an error' do
      let(:handler) { ->(request, fake) { fake.reply_error(request, code: 3, message: 'Duplicate key') } }

      it 'raises ServerError with the error code' do
        expect { connection.perform(eval_request('x'), timeout: 1) }
          .to raise_error(Tarantool::ServerError, 'Duplicate key') { |error| expect(error.code).to eq(3) }
      end

      it 'carries the schema version from the error response' do
        expect { connection.perform(eval_request('x'), timeout: 1) }
          .to raise_error(Tarantool::ServerError) { |error| expect(error.schema_version).to eq(1) }
      end
    end

    context 'when the server pushes before replying' do
      let(:handler) do
        lambda do |request, fake|
          fake.push(request, ['progress'])
          fake.reply(request, ['done'])
        end
      end

      it 'returns the final reply' do
        expect(connection.perform(eval_request('x'), timeout: 1).data).to eq(['done'])
      end

      it 'passes each pushed message to on_push' do
        messages = []
        connection.perform(eval_request('x'), timeout: 1, on_push: ->(message) { messages << message })

        expect(messages).to eq(['progress'])
      end

      it 'raises the on_push error and stays usable' do
        expect { connection.perform(eval_request('x'), timeout: 1, on_push: ->(_message) { raise 'boom' }) }
          .to raise_error(RuntimeError, 'boom')
        expect(connection.perform(eval_request('x'), timeout: 1).data).to eq(['done'])
      end
    end

    context 'when an event carries the sync of a pending request' do
      let(:handler) do
        lambda do |request, fake|
          fake.event('k', 1, sync: request.sync)
          fake.reply(request, ['done'])
        end
      end

      it 'resolves the request with its reply, not the event' do
        expect(connection.perform(eval_request('x'), timeout: 1).data).to eq(['done'])
      end
    end

    context 'when on_push is slow' do
      let(:handler) do
        lambda do |request, fake|
          fake.push(request, ['tick']) if request.body[0x27] == 'slow'
          fake.reply(request, [request.body[0x27]])
        end
      end

      it 'keeps answering other requests' do
        slow = Thread.new { connection.perform(eval_request('slow'), timeout: 2, on_push: ->(_message) { sleep 0.5 }) }
        sleep 0.05
        started = Tarantool::Client::Transport::Deadline.now

        expect(connection.perform(eval_request('fast'), timeout: 1).data).to eq(['fast'])
        expect(Tarantool::Client::Transport::Deadline.now - started).to be < 0.25
        slow.join
      end
    end

    context 'when the server keeps pushing without replying' do
      let(:handler) do
        lambda do |request, fake|
          10.times do
            fake.push(request, ['tick'])
            sleep 0.05
          end
        end
      end

      it 'bounds the request by one timeout' do
        started = Tarantool::Client::Transport::Deadline.now

        expect { connection.perform(eval_request('x'), timeout: 0.2, on_push: ->(_message) {}) }
          .to raise_error(Tarantool::TimeoutError, 'no response within 0.2s')
        expect(Tarantool::Client::Transport::Deadline.now - started).to be < 0.4
      end
    end

    context 'when the server sends a malformed frame' do
      let(:handler) { ->(_request, fake) { fake.send_raw("\xff" * 5) } }

      it 'raises ConnectionError' do
        expect { connection.perform(eval_request('x'), timeout: 1) }.to raise_error(Tarantool::ConnectionError, /lost/)
      end
    end

    context 'when the server stops reading' do
      let(:handler) { ->(_request, _fake) { sleep } }

      before do
        connection.perform(eval_request('stall'), timeout: 0.05)
      rescue Tarantool::TimeoutError
        nil
      end

      it 'raises TimeoutError when the write misses the deadline' do
        large = eval_request('x' * 8_000_000)

        expect { Timeout.timeout(2) { connection.perform(large, timeout: 0.2) } }.to raise_error(Tarantool::TimeoutError)
      end

      it 'marks the connection dead after an incomplete write' do
        large = eval_request('x' * 8_000_000)

        expect { Timeout.timeout(2) { connection.perform(large, timeout: 0.2) } }.to raise_error(Tarantool::TimeoutError)
        expect { connection.perform(eval_request('x'), timeout: 1) }.to raise_error(Tarantool::ConnectionError)
      end
    end

    context 'when the server drops the connection' do
      let(:handler) { ->(_request, fake) { fake.disconnect } }

      it 'raises ConnectionError' do
        expect { connection.perform(eval_request('x'), timeout: 1) }.to raise_error(Tarantool::ConnectionError, /lost/)
      end
    end

    it 'matches out-of-order responses by sync' do
      threads = %w[first second].map { |expr| Thread.new { connection.perform(eval_request(expr), timeout: 1).data } }
      requests = Array.new(2) { server.next_request }
      requests.reverse_each { |request| server.reply(request, [request.body[0x27]]) }

      expect(threads.map(&:value)).to eq([['first'], ['second']])
    end

    it 'raises TimeoutError when the server stays silent' do
      expect { connection.perform(eval_request('x'), timeout: 0.05) }
        .to raise_error(Tarantool::TimeoutError, 'no response within 0.05s')
    end

    it 'fails a waiting request with ClientClosedError on close' do
      connection
      waiter = Thread.new do
        connection.perform(eval_request('x'), timeout: 1)
      rescue Tarantool::Error => e
        e.class
      end
      server.next_request
      connection.close

      expect(waiter.value).to eq(Tarantool::ClientClosedError)
    end

    it 'raises ClientClosedError after close' do
      connection.close

      expect { connection.perform(eval_request('x'), timeout: 1) }.to raise_error(Tarantool::ClientClosedError)
    end
  end

  describe 'losing the connection' do
    let(:lost) { Thread::Queue.new }
    let(:connection) do
      described_class.new(config).tap { |c| c.disconnect_handler = -> { lost << c.closed? } }.connect
    end

    after { connection.close }

    it 'calls the disconnect handler once, after the connection is marked closed' do
      connection
      server.disconnect

      expect(lost.pop(timeout: 1)).to be(true)
      expect(lost.pop(timeout: 0.1)).to be_nil
    end

    it 'does not call the disconnect handler on close' do
      connection.close

      expect(lost.pop(timeout: 0.1)).to be_nil
    end

    it 'is not closed while connected' do
      expect(connection.closed?).to be(false)
    end
  end

  describe '#notify' do
    let(:watch) { Tarantool::Client::Protocol::Requests::Watch.new(key: 'box.status') }

    after { connection.close }

    it 'writes a request without waiting for a reply' do
      connection.notify(watch, timeout: 1)

      expect(server.next_request).to have_attributes(type: 0x4a, body: { 0x57 => 'box.status' })
    end

    it 'raises ClientClosedError after close' do
      connection.close

      expect { connection.notify(watch, timeout: 1) }.to raise_error(Tarantool::ClientClosedError)
    end
  end

  describe 'events' do
    after { connection.close }

    it 'hands event keys and values to the event handler' do
      events = Thread::Queue.new
      connection.event_handler = ->(key, value) { events << [key, value] }
      server.event('box.status', { 'is_ro' => false })
      server.event('app.state')

      expect(Array.new(2) { events.pop(timeout: 1) }).to eq([['box.status', { 'is_ro' => false }], ['app.state', nil]])
    end
  end
end
