# frozen_string_literal: true

RSpec.describe Tarantool::Client::CachedStatements, :integration do
  let(:uri) { ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301') }
  let(:instrumenter) { RecordingInstrumenter.new }
  let(:client) { Tarantool::Client.new(uri, statement_cache: 10, instrumenter:) }
  let(:sql) { 'SELECT "id", "email" FROM "users" WHERE "id" = ?' }

  after { client.close }

  def requests = instrumenter.payloads('request.tarantool').map { |payload| payload[:request] }

  it 'prepares once and executes by id afterwards' do
    rows = Array.new(3) { client.execute(sql, [1]).rows }

    expect(rows.uniq.size).to eq(1)
    expect(requests.tally).to eq(prepare: 1, execute: 3)
    expect(instrumenter.payloads('request.tarantool').last).to include(request: :execute, statement_id: Integer)
  end

  it 'returns the same rows and columns as an execute without the cache' do
    plain = Tarantool::Client.new(uri)
    expected = plain.execute(sql, [1])
    plain.close

    expect(client.execute(sql, [1])).to have_attributes(rows: expected.rows, columns: expected.columns)
  end

  it 'recovers after a prepared statement is dropped on the server' do
    client.execute(sql, [1])
    client.eval('box.unprepare(...)', [instrumenter.payloads('request.tarantool').last[:statement_id]])

    expect(client.execute(sql, [1]).columns).to eq(%w[id email])
    expect(requests.tally).to eq(prepare: 2, execute: 3, eval: 1)
  end

  it 'recovers after a schema change expired the statement' do
    client.execute(sql, [1])
    client.eval("box.schema.space.create('cache_probe'):drop()")

    expect(client.execute(sql, [1]).columns).to eq(%w[id email])
    expect(requests.tally).to eq(prepare: 2, execute: 3, eval: 1)
  end

  it 'works over a pool' do
    pool = Tarantool::Client::Pool.new([uri], statement_cache: 10, instrumenter:)
    2.times { pool.execute(sql, [1]) }

    expect(requests.tally).to eq(prepare: 1, execute: 2)
  ensure
    pool&.close
  end
end
