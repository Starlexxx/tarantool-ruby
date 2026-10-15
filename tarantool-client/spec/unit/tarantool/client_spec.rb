# frozen_string_literal: true

RSpec.describe Tarantool::Client do
  context 'with a connected client' do
    let(:handler) do
      lambda do |request, fake|
        space_id = request.body[0x10]
        case space_id
        when 281 then fake.reply(request, [[512, 1, 'users']])
        when 289 then fake.reply(request, [[512, 0, 'primary']])
        else fake.reply(request, [[space_id, request.body[0x20]]])
        end
      end
    end
    let(:server) { FakeTarantool.new(&handler) }
    let(:client) { described_class.new(server.uri, user: 'app', password: 'secret') }

    after do
      client.close
      server.stop
    end

    it 'shows only the address when inspected' do
      expect(client.inspect).to eq("#<Tarantool::Client #{server.path}>")
    end

    it 'reports the server version' do
      expect(client.server_version).to eq('2.11.1')
    end

    it 'resolves names through the loaded schema' do
      expect(client.select(:users, 7, index: :primary)).to eq([[512, [7]]])
    end

    context 'when a name becomes known after a reload' do
      let!(:schema_state) { { orders: false } }
      let(:handler) do
        lambda do |request, fake|
          space_id = request.body[0x10]
          case space_id
          when 281
            rows = [[512, 1, 'users']]
            rows << [600, 1, 'orders'] if schema_state[:orders]
            fake.reply(request, rows)
          when 289 then fake.reply(request, [[512, 0, 'primary']])
          else fake.reply(request, [[space_id, request.body[0x20]]])
          end
        end
      end

      it 'resolves the name once the schema is reloaded and includes it' do
        expect { client.select(:orders, 1) }.to raise_error(Tarantool::SchemaError)

        schema_state[:orders] = true

        expect(client.select(:orders, 1)).to eq([[600, [1]]])
      end
    end

    it 'reloads the schema once before raising SchemaError for an unknown name' do
      client
      before = server.headers.count { |header| header[0x00] == 0x01 }

      expect { client.select(:orders, 1) }.to raise_error(Tarantool::SchemaError)
      expect(server.headers.count { |header| header[0x00] == 0x01 }).to eq(before + 2)
    end

    it 'sends the schema version with requests resolved by name' do
      client.select(:users, 1)

      expect(server.headers.last[0x05]).to eq(1)
    end

    it 'sends no schema version for numeric space and index ids' do
      client.select(512, 1, index: 0)

      expect(server.headers.last).not_to have_key(0x05)
    end

    describe '#transaction' do
      def stream_requests
        server.headers.select { |header| header.key?(0x0a) }.map { |header| [header[0x00], header[0x0a]] }
      end

      it 'runs each transaction on a new stream' do
        2.times { client.transaction(&:ping) }

        expect(stream_requests).to eq([[0x0e, 1], [0x40, 1], [0x0f, 1], [0x0e, 2], [0x40, 2], [0x0f, 2]])
      end

      it 'rejects a nested transaction on the same client and rolls back the outer one' do
        expect { client.transaction { client.transaction { nil } } }
          .to raise_error(Tarantool::TransactionError, 'nested transactions are not supported')
        expect(stream_requests).to eq([[0x0e, 1], [0x10, 1]])
      end

      it 'lets a thread started inside a transaction open its own' do
        expect(client.transaction { Thread.new { client.transaction { :inner } }.value }).to eq(:inner)
      end

      it 'allows a new transaction after a failed one' do
        expect { client.transaction { raise 'boom' } }.to raise_error(RuntimeError, 'boom')
        expect(client.transaction { :again }).to eq(:again)
      end

      it 'rejects an unknown isolation level before sending anything' do
        expect { client.transaction(isolation: :serializable) { nil } }.to raise_error(ArgumentError)
        expect(stream_requests).to eq([])
      end
    end
  end

  context 'with a server that pushes' do
    let(:server) do
      FakeTarantool.new do |request, fake|
        if request.type == 0x0a
          fake.push(request, ['started'])
          fake.reply(request, ['done'])
        else
          fake.reply(request, [])
        end
      end
    end
    let(:client) { described_class.new(server.uri) }

    after do
      client.close
      server.stop
    end

    it 'passes pushed messages to on_push and returns the final reply' do
      messages = []

      expect(client.call('job', on_push: ->(message) { messages << message })).to eq(['done'])
      expect(messages).to eq(['started'])
    end
  end

  context 'when another client changes the schema' do
    let!(:schema_state) { { users_id: 512, vspace_requests: 0, churn: false } }
    let(:server) { FakeTarantool.new(check_schema_version: true, &handler) }
    let(:client) { described_class.new(server.uri, user: 'app', password: 'secret') }
    let(:handler) do
      lambda do |request, fake|
        case request.body[0x10]
        when 281 then reply_vspace(request, fake)
        when 289 then reply_vindex(request, fake)
        else fake.reply(request, [[request.body[0x10], request.body[0x20]]])
        end
      end
    end

    def reply_vspace(request, fake)
      schema_state[:vspace_requests] += 1
      sleep schema_state[:delay].to_f
      fake.reply(request, [[schema_state[:users_id], 1, 'users']])
      fake.schema_version += 1 if schema_state[:churn]
    end

    def reply_vindex(request, fake)
      sleep schema_state[:delay].to_f
      fake.reply(request, [[schema_state[:users_id], 0, 'primary']])
    end

    before do
      client
      schema_state[:users_id] = 513
      server.schema_version = 2
    end

    after do
      client.close
      server.stop
    end

    it 'reloads once and retries with the new ids' do
      expect(client.select(:users, 1, index: :primary)).to eq([[513, [1]]])
      expect(schema_state[:vspace_requests]).to eq(2)
    end

    it 'raises ServerError when the retry also hits a stale schema' do
      schema_state[:churn] = true

      expect { client.select(:users, 1) }
        .to raise_error(Tarantool::ServerError) { |error| expect(error.code).to eq(109) }
      expect(schema_state[:vspace_requests]).to eq(2)
    end

    it 'performs a single reload when many threads hit a stale schema concurrently' do
      threads = Array.new(10) { Thread.new { client.select(:users, 1, index: :primary) } }

      expect(threads.map(&:value)).to all(eq([[513, [1]]]))
      expect(schema_state[:vspace_requests]).to eq(2)
    end

    it 'reloads the schema within the request timeout' do
      schema_state[:delay] = 0.5

      expect { client.select(:users, 1, timeout: 0.1) }.to raise_error(Tarantool::TimeoutError)
    end

    it 'bounds the stale request, reload and retry by one timeout' do
      schema_state[:delay] = 0.25
      started = Tarantool::Client::Transport::Deadline.now

      expect { client.select(:users, 1, index: :primary, timeout: 0.3) }
        .to raise_error(Tarantool::TimeoutError, 'no response within 0.3s')
      expect(Tarantool::Client::Transport::Deadline.now - started).to be < 0.6
    end

    it 'does not send the retry once the reload used up the timeout' do
      schema_state[:delay] = 0.15

      expect { client.select(:users, 1, timeout: 0.2) }.to raise_error(Tarantool::TimeoutError)
      client.select(512, 1, index: 0)
      expect(server.headers.count { |header| header[0x00] == 0x01 && header.key?(0x05) }).to eq(1)
    end
  end

  context 'with watchers' do
    let!(:watch_requests) { Thread::Queue.new }
    let(:server) do
      FakeTarantool.new do |request, fake|
        next watch_requests << request if [0x4a, 0x4b].include?(request.type)

        fake.reply(request, [])
      end
    end
    let(:client) { described_class.new(server.uri) }
    let(:events) { Thread::Queue.new }

    after do
      client.close
      server.stop
    end

    it 'subscribes with WATCH and passes events to the block' do
      client.watch('config') { |key, value| events << [key, value] }

      expect(watch_requests.pop(timeout: 1)).to have_attributes(type: 0x4a, body: { 0x57 => 'config' })
      server.event('config', { 'a' => 1 })
      expect(events.pop(timeout: 1)).to eq(['config', { 'a' => 1 }])
    end

    it 'acknowledges each event with another WATCH' do
      client.watch('config') { |key, value| events << [key, value] }
      watch_requests.pop(timeout: 1)
      server.event('config', 1)
      events.pop(timeout: 1)

      expect(watch_requests.pop(timeout: 1)).to have_attributes(type: 0x4a, body: { 0x57 => 'config' })
    end

    it 'sends UNWATCH when the watcher is removed' do
      client.watch('config') { nil }.unwatch
      watch_requests.pop(timeout: 1)

      expect(watch_requests.pop(timeout: 1)).to have_attributes(type: 0x4b, body: { 0x57 => 'config' })
    end

    it 'requires a block' do
      expect { client.watch('config') }.to raise_error(ArgumentError, 'watch requires a block')
    end

    it 'stops the dispatcher thread on close' do
      client.watch('config') { nil }
      client.close

      expect(Thread.list.none? { |thread| thread.name == 'tarantool-watchers' && thread.alive? }).to be(true)
    end

    it 'raises ClientClosedError when watching a key again after close' do
      client.watch('config') { nil }
      client.close

      expect { client.watch('config') { nil } }.to raise_error(Tarantool::ClientClosedError)
    end
  end

  context 'when the initial schema load fails' do
    it 'closes the connection and re-raises' do
      failing = FakeTarantool.new { |request, fake| fake.reply_error(request, code: 1, message: 'boom') }

      expect { described_class.new(failing.uri, user: 'app', password: 'secret') }
        .to raise_error(Tarantool::ServerError, 'boom')
      expect(Thread.list.none? { |t| t.name&.start_with?('tarantool-reader') }).to be(true)
    ensure
      failing.stop
    end
  end
end
