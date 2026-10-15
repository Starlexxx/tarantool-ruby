# frozen_string_literal: true

RSpec.describe Tarantool::Client::Stream do
  subject(:stream) { described_class.new(connection:, schema_cache:, id: 1, request_timeout: 1) }

  let(:handler) do
    lambda do |request, fake|
      case request.body[0x10]
      when 281 then fake.reply(request, [[512, 1, 'users']])
      when 289 then fake.reply(request, [[512, 0, 'primary']])
      else fake.reply(request, [[request.type, request.body[0x10]]])
      end
    end
  end
  let(:server) { FakeTarantool.new(check_schema_version: true, &handler) }
  let(:connection) do
    Tarantool::Client::Transport::Connection.new(Tarantool::Client::Configuration.build(server.uri)).connect
  end
  let(:schema_cache) { Tarantool::Client::SchemaCache.new(connection).tap { |cache| cache.reload(timeout: 1) } }

  after do
    connection.close
    server.stop
  end

  def stream_requests
    server.headers.select { |header| header.key?(0x0a) }.map { |header| [header[0x00], header[0x0a]] }
  end

  def transaction(&) = stream.transaction(isolation: :default, timeout: nil, &)

  it 'begins, runs the block in the stream, commits and returns the block value' do
    result = stream.transaction(isolation: :read_committed, timeout: 2) { |tx| tx.insert(:users, [1]) }

    expect(result).to eq([0x02, 512])
    expect(stream_requests).to eq([[0x0e, 1], [0x02, 1], [0x0f, 1]])
  end

  it 'rolls back and re-raises when the block raises' do
    expect { transaction { raise 'boom' } }.to raise_error(RuntimeError, 'boom')
    expect(stream_requests).to eq([[0x0e, 1], [0x10, 1]])
  end

  it 'rolls back when the block exits early' do
    stream.transaction(isolation: :default, timeout: nil) { break }

    expect(stream_requests).to eq([[0x0e, 1], [0x10, 1]])
  end

  it 'rejects operations once the transaction is finished' do
    finished = transaction { |tx| tx }

    expect { finished.ping }.to raise_error(Tarantool::TransactionError, 'transaction is finished')
  end

  it 'rejects a nested transaction and keeps the outer one usable' do
    transaction do |tx|
      expect { tx.transaction(isolation: :default, timeout: nil) { nil } }
        .to raise_error(Tarantool::TransactionError, 'nested transactions are not supported')
      tx.ping
    end

    expect(stream_requests).to eq([[0x0e, 1], [0x40, 1], [0x0f, 1]])
  end

  it 'sends names resolved against the schema version of BEGIN' do
    transaction { |tx| tx.select(:users, 1) }

    expect(server.headers.find { |header| header[0x00] == 0x01 && header.key?(0x0a) }[0x05]).to eq(1)
  end

  it 'catches up with a schema that changed before BEGIN' do
    schema_cache
    server.schema_version = 2

    expect(transaction { |tx| tx.select(:users, 1) }).to eq([[0x01, 512]])
    expect(schema_cache.schema.version).to eq(2)
  end

  context 'when the schema changes after BEGIN' do
    def mid_tx_schema_change
      transaction do |tx|
        server.schema_version = 2
        tx.select(:users, 1)
      end
    end

    it 'raises TransactionError whose cause is the schema-version server error' do
      expect { mid_tx_schema_change }
        .to raise_error(Tarantool::TransactionError, /schema changed/) { |e| expect(e.cause.code).to eq(109) }
    end

    it 'rolls back and refreshes the schema cache' do
      expect { mid_tx_schema_change }.to raise_error(Tarantool::TransactionError)
      expect(stream_requests.last).to eq([0x10, 1])
      expect(schema_cache.schema.version).to eq(2)
    end
  end

  context 'when the rollback fails' do
    let(:handler) do
      lambda do |request, fake|
        next fake.reply_error(request, code: 1, message: 'rollback failed') if request.type == 0x10

        fake.reply(request, request.body[0x10] == 281 ? [[512, 1, 'users']] : [[512, 0, 'primary']])
      end
    end

    it 'raises the error from the block' do
      expect { transaction { raise 'boom' } }.to raise_error(RuntimeError, 'boom')
    end
  end
end
