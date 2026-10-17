# frozen_string_literal: true

OTHER_SQL = 'SELECT 1'

RSpec.describe Tarantool::Client::CachedStatements do
  let(:sql) { 'SELECT "id" FROM "users" WHERE "id" = ?' }
  let(:log) { Thread::Queue.new }
  let(:failures) { Thread::Queue.new }
  let(:server) do
    FakeTarantool.new do |request, fake|
      case request.type
      when 0x0d then prepare(request, fake)
      when 0x0b then execute(request, fake)
      when 0x01 then fake.reply(request, [])
      end
    end
  end
  let(:client) { Tarantool::Client.new(server.uri, statement_cache: 2, reconnect_delay: 0.01) }

  after do
    client.close
    server.stop
  end

  def prepare(request, fake)
    if request.body.key?(0x43)
      log << [:unprepare, request.body[0x43]]
      fake.reply(request)
    else
      log << [:prepare, request.body[0x40]]
      fake.reply(request, [], { 0x43 => request.body[0x40].size })
    end
  end

  def execute(request, fake)
    log << [:execute, request.body[0x43] || request.body[0x40]]
    failure = failures.pop(timeout: 0)
    return fake.reply_error(request, code: failure.first, message: failure.last) if failure

    fake.reply(request, [[1]])
  end

  def drain(queue) = Array.new(queue.size) { queue.pop }

  it 'prepares on the first execute and reuses the id afterwards' do
    2.times { client.execute(sql, [1]) }

    expect(drain(log)).to eq([[:prepare, sql], [:execute, sql.size], [:execute, sql.size]])
  end

  it 'returns the rows of the cached execute' do
    expect(client.execute(sql, [1]).rows).to eq([[1]])
  end

  it 'sends the text without the option' do
    plain = Tarantool::Client.new(server.uri)
    plain.execute(sql, [1])
    plain.close

    expect(drain(log)).to eq([[:execute, sql]])
  end

  it 'bypasses the cache for a prepared statement and an id' do
    statement = client.prepare(OTHER_SQL)
    client.execute(statement)
    client.execute(statement.id)

    expect(drain(log)).to eq([[:prepare, OTHER_SQL], [:execute, OTHER_SQL.size], [:execute, OTHER_SQL.size]])
  end

  it 'unprepares the statement evicted at the limit' do
    [sql, OTHER_SQL, 'SELECT 22'].each { |text| client.execute(text) }

    expect(drain(log)).to include([:unprepare, sql.size])
    expect(drain(log)).to be_empty
  end

  it 'prepares again after the connection is lost' do
    client.execute(sql, [1])
    server.disconnect
    wait_for { server.connections == 2 && client.connected? }
    client.execute(sql, [1])

    expect(drain(log).count { |event, _| event == :prepare }).to eq(2)
  end

  it 'prepares again once when the server no longer knows the id' do
    client.execute(sql, [1])
    failures << [211, 'Prepared statement with id 7 does not exist']

    expect(client.execute(sql, [1]).rows).to eq([[1]])
    expect(drain(log)).to eq([[:prepare, sql], [:execute, sql.size], [:execute, sql.size], [:prepare, sql],
                              [:execute, sql.size]])
  end

  it 'raises when the fresh statement is unknown too' do
    client.execute(sql, [1])
    2.times { failures << [211, 'Prepared statement with id 7 does not exist'] }

    expect { client.execute(sql, [1]) }.to raise_error(Tarantool::ServerError) { |error| expect(error.code).to eq(211) }
  end

  it 'prepares again once when the statement expired after a schema change' do
    client.execute(sql, [1])
    failures << [159, 'Failed to execute SQL statement: statement has expired']

    expect(client.execute(sql, [1]).rows).to eq([[1]])
    expect(drain(log).count { |event, _| event == :prepare }).to eq(2)
  end

  it 'does not retry another execute failure' do
    client.execute(sql, [1])
    failures << [159, 'Failed to execute SQL statement: boom']

    expect { client.execute(sql, [1]) }.to raise_error(Tarantool::ServerError, /boom/)
    expect(drain(log).count { |event, _| event == :prepare }).to eq(1)
  end

  it 'ignores an error on the unprepare of an evicted statement' do
    unprepare_fails = FakeTarantool.new do |request, fake|
      next fake.reply_error(request, code: 1, message: 'boom') if request.type == 0x0d && request.body.key?(0x43)

      request.type == 0x0d ? fake.reply(request, [], { 0x43 => request.body[0x40].size }) : fake.reply(request, [[1]])
    end
    small = Tarantool::Client.new(unprepare_fails.uri, statement_cache: 1)

    expect([sql, OTHER_SQL].map { |text| small.execute(text).rows }).to eq([[[1]], [[1]]])
  ensure
    small&.close
    unprepare_fails&.stop
  end
end
