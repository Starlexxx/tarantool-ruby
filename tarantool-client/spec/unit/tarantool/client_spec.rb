# frozen_string_literal: true

RSpec.describe Tarantool::Client do
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

  it 'reports the server version' do
    expect(client.server_version).to eq('2.11.1')
  end

  it 'resolves names through the loaded schema' do
    expect(client.select(:users, 7, index: :primary)).to eq([[512, [7]]])
  end

  it 'raises SchemaError for unknown names after a reload' do
    expect { client.select(:orders, 1) }.to raise_error(Tarantool::SchemaError)
  end

  context 'when a name becomes known after a reload' do
    # Handlers run on FakeTarantool's own thread. Touching a `let` there for the
    # first time while `client` is still connecting on the main thread deadlocks
    # on RSpec's per-example memoization mutex, so memoize it here first.
    let(:schema_state) { { orders: false } }
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
      schema_state

      expect { client.select(:orders, 1) }.to raise_error(Tarantool::SchemaError)

      schema_state[:orders] = true

      expect(client.select(:orders, 1)).to eq([[600, [1]]])
    end
  end

  context 'when the schema version advances' do
    # See the comment above for why this is memoized before `client` connects.
    let(:vspace_requests) { [] }
    let(:handler) do
      lambda do |request, fake|
        space_id = request.body[0x10]
        case space_id
        when 281
          vspace_requests << request
          fake.reply(request, [[512, 1, 'users']])
        when 289 then fake.reply(request, [[512, 0, 'primary']])
        else fake.reply(request, [[space_id, request.body[0x20]]])
        end
      end
    end

    it 'reloads once after a response carries a newer schema_version' do
      vspace_requests
      client
      before = vspace_requests.size
      server.schema_version = 2
      client.select(:users, 1)

      expect(vspace_requests.size).to eq(before)

      client.select(:users, 1, index: :primary)

      expect(vspace_requests.size).to eq(before + 1)
    end

    it 'performs a single reload when many threads resolve concurrently' do
      vspace_requests
      client
      server.schema_version = 2
      client.select(:users, 1)
      before = vspace_requests.size

      threads = Array.new(10) { Thread.new { client.select(:users, 1, index: :primary) } }
      threads.each(&:join)

      expect(vspace_requests.size).to eq(before + 1)
    end

    it 'skips schema resolution and reload for numeric space and index ids' do
      vspace_requests
      client
      server.schema_version = 2
      client.select(:users, 1)
      before = vspace_requests.size

      client.select(512, 7, index: 0)

      expect(vspace_requests.size).to eq(before)
    end
  end

  it 'closes the connection and re-raises when the initial schema load fails' do
    failing = FakeTarantool.new { |request, fake| fake.reply_error(request, code: 1, message: 'boom') }

    expect { described_class.new(failing.uri, user: 'app', password: 'secret') }
      .to raise_error(Tarantool::ServerError, 'boom')
    expect(Thread.list.none? { |t| t.name&.start_with?('tarantool-reader') }).to be(true)
  ensure
    failing.stop
  end
end
