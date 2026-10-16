# frozen_string_literal: true

RSpec.describe Tarantool::Client::TransactionSchema do
  let(:server) do
    FakeTarantool.new do |request, fake|
      fake.reply(request, request.body[0x10] == 281 ? [[512, 1, 'users']] : [[512, 0, 'primary']])
    end
  end
  let(:connection) do
    Tarantool::Client::Transport::Connection.new(Tarantool::Client::Configuration.build(server.uri)).connect
  end
  let(:cache) do
    Tarantool::Client::SchemaCache.new.tap { |cache| cache.replace(Tarantool::Client::Schema.fetch(connection, timeout: 1)) }
  end
  let(:deadline) { Tarantool::Client::Transport::Deadline.after(1) }

  after do
    connection.close
    server.stop
  end

  def schema_selects = server.headers.count { |header| header[0x00] == 0x01 }

  it 'resolves names with the cached schema of the BEGIN version' do
    expect(described_class.new(cache, connection, 1).resolve(:users, :primary, deadline)).to eq([[512, 0], false])
    expect(schema_selects).to eq(2)
  end

  it 'returns space info from the schema of the BEGIN version' do
    expect(described_class.new(cache, connection, 1).space_info(:users, deadline).indexes.keys).to eq(['primary'])
  end

  it 'raises TransactionError for space info once the schema moved past the BEGIN version' do
    cache
    server.schema_version = 3

    expect { described_class.new(cache, connection, 2).space_info(:users, deadline) }
      .to raise_error(Tarantool::TransactionError, /schema changed/)
  end

  it 'reloads a cache older than the BEGIN version' do
    cache
    server.schema_version = 2

    expect(described_class.new(cache, connection, 2).resolve(:users, 0, deadline)).to eq([[512, 0], true])
    expect(cache.schema.version).to eq(2)
  end

  it 'raises TransactionError when the schema moved past the BEGIN version' do
    cache
    server.schema_version = 3

    expect { described_class.new(cache, connection, 2).resolve(:users, 0, deadline) }
      .to raise_error(Tarantool::TransactionError, /schema changed/)
  end

  it 'raises SchemaError for a name unknown at the BEGIN version without reloading' do
    expect { described_class.new(cache, connection, 1).resolve(:orders, 0, deadline) }.to raise_error(Tarantool::SchemaError)
    expect(schema_selects).to eq(2)
  end

  it 'raises TransactionError for a cache holding the schema of another connection' do
    cache.replace(Tarantool::Client::Schema.new(version: 1, spaces: [[512, 1, 'users']], indexes: []))

    expect { described_class.new(cache, connection, 1).resolve(:users, 0, deadline) }
      .to raise_error(Tarantool::TransactionError, /connection lost/)
  end

  it 'refreshes the cache for a rejected request and reports the reload' do
    cache
    server.schema_version = 2

    expect(described_class.new(cache, connection, 1).refresh?(deadline)).to be(true)
    expect(cache.schema.version).to eq(2)
  end

  it 'does not reload for a rejected request once the cache moved past the BEGIN version' do
    cache
    server.schema_version = 2
    cache.reload(cache.schema, timeout: 1)

    expect(described_class.new(cache, connection, 1).refresh?(deadline)).to be(false)
  end
end
