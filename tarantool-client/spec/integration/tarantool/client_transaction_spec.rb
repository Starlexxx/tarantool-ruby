# frozen_string_literal: true

RSpec.describe Tarantool::Client, :integration do
  subject(:client) { described_class.new(uri) }

  let(:uri) { ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301') }
  let(:observer) { described_class.new(uri) }

  def drop_spaces
    client.eval("for _, n in ipairs({'sql_tx', 'sql_tx_ddl'}) do if box.space[n] then box.space[n]:drop() end end")
  end

  before do
    drop_spaces
    client.execute('CREATE TABLE "sql_tx" ("id" INTEGER PRIMARY KEY, "name" STRING)')
  end

  after do
    drop_spaces
    observer.close
    client.close
  end

  it 'commits the block and returns its value' do
    result = client.transaction(isolation: :read_committed, timeout: 5) do |tx|
      tx.insert(:sql_tx, [1, 'a'])
      :done
    end

    expect(result).to eq(:done)
    expect(observer.select(:sql_tx)).to eq([[1, 'a']])
  end

  it 'hides uncommitted writes from other connections' do
    client.transaction do |tx|
      tx.insert(:sql_tx, [1, 'a'])
      expect(observer.select(:sql_tx)).to eq([])
    end

    expect(observer.select(:sql_tx)).to eq([[1, 'a']])
  end

  it 'rolls back and re-raises when the block raises' do
    expect do
      client.transaction do |tx|
        tx.insert(:sql_tx, [1, 'a'])
        raise 'boom'
      end
    end.to raise_error(RuntimeError, 'boom')
    expect(client.select(:sql_tx)).to eq([])
  end

  it 'rolls back SQL run inside the transaction' do
    expect do
      client.transaction do |tx|
        tx.execute('INSERT INTO "sql_tx" VALUES (?, ?)', [1, 'a'])
        raise 'boom'
      end
    end.to raise_error(RuntimeError, 'boom')
    expect(client.execute('SELECT COUNT(*) FROM "sql_tx"').rows).to eq([[0]])
  end

  it 'runs a prepared statement inside the transaction' do
    statement = client.prepare('INSERT INTO "sql_tx" VALUES (?, ?)')
    expect do
      client.transaction do |tx|
        tx.execute(statement, [1, 'a'])
        raise 'boom'
      end
    end.to raise_error(RuntimeError, 'boom')
    expect(client.execute('SELECT COUNT(*) FROM "sql_tx"').rows).to eq([[0]])
    statement.close
  end

  it 'raises TransactionError for a nested transaction and rolls back the outer one' do
    expect do
      client.transaction do |tx|
        tx.insert(:sql_tx, [1, 'a'])
        client.transaction { nil }
      end
    end.to raise_error(Tarantool::TransactionError, 'nested transactions are not supported')
    expect(client.select(:sql_tx)).to eq([])
  end

  it 'raises the server error once the transaction timeout expires' do
    expect do
      client.transaction(timeout: 0.1) do |tx|
        tx.insert(:sql_tx, [1, 'a'])
        sleep 0.3
        tx.insert(:sql_tx, [2, 'b'])
      end
    end.to raise_error(Tarantool::ServerError) { |error| expect(error.code).to eq(231) }
  end

  it 'fails a transaction whose schema changed and lets the retry succeed' do
    expect do
      client.transaction do |tx|
        tx.insert(:sql_tx, [1, 'a'])
        observer.eval("box.schema.space.create('sql_tx_ddl')")
        tx.insert(:sql_tx, [2, 'b'])
      end
    end.to raise_error(Tarantool::TransactionError, /schema changed/)
    client.transaction { |tx| tx.insert(:sql_tx, [3, 'c']) }
    expect(client.select(:sql_tx)).to eq([[3, 'c']])
  end
end
