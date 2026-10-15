# frozen_string_literal: true

RSpec.describe Tarantool::Client::SchemaCache do
  subject(:cache) { described_class.new }

  let(:schema_state) { { vspace_requests: 0, spaces: [[512, 1, 'users']] } }
  let(:server) do
    FakeTarantool.new do |request, fake|
      next fake.reply(request, [[512, 0, 'primary']]) unless request.body[0x10] == 281

      schema_state[:vspace_requests] += 1
      sleep schema_state.fetch(:delay, 0.05)
      fake.reply(request, schema_state[:spaces])
    end
  end
  let(:connection) do
    Tarantool::Client::Transport::Connection.new(Tarantool::Client::Configuration.build(server.uri)).connect
  end
  let(:deadline) { Tarantool::Client::Transport::Deadline.after(1) }

  after do
    connection.close
    server.stop
  end

  def load_schema = cache.tap { cache.replace(Tarantool::Client::Schema.fetch(connection, timeout: 1)) }.schema

  it 'reloads a stale schema over the connection it was loaded from' do
    stale = load_schema

    fresh = cache.reload(stale, timeout: 1)

    expect(fresh).not_to be(stale)
    expect(fresh.connection).to be(connection)
  end

  it 'fetches once when many threads reload the same stale schema' do
    stale = load_schema
    threads = Array.new(5) { Thread.new { cache.reload(stale, timeout: 1) } }

    expect(threads.map(&:value).uniq.size).to eq(1)
    expect(schema_state[:vspace_requests]).to eq(2)
  end

  it 'keeps a schema newer than the stale one' do
    stale = load_schema
    fresh = cache.reload(stale, timeout: 1)

    expect(cache.reload(stale, timeout: 1)).to be(fresh)
  end

  it 'reloads once to resolve a name created after the last load' do
    load_schema
    schema_state[:spaces] = [[512, 1, 'users'], [600, 1, 'orders']]

    expect(cache.resolve(:orders, 0, deadline).last).to eq([600, 0])
  end

  it 'raises SchemaError when the name is still unknown after one reload' do
    load_schema

    expect { cache.resolve(:orders, 0, deadline) }.to raise_error(Tarantool::SchemaError)
    expect(schema_state[:vspace_requests]).to eq(2)
  end

  it 'bounds the wait for a reload running in another thread by the timeout' do
    stale = load_schema
    schema_state[:delay] = 0.5
    slow = Thread.new { cache.reload(stale, timeout: 1) }
    sleep 0.05
    started = Tarantool::Client::Transport::Deadline.now

    expect { cache.reload(stale, timeout: 0.1) }.to raise_error(Tarantool::TimeoutError)
    expect(Tarantool::Client::Transport::Deadline.now - started).to be < 0.3
    slow.join
  end

  it 'serves a replaced schema without fetching' do
    stale = load_schema
    replaced = Tarantool::Client::Schema.new(version: 2, spaces: [[600, 1, 'orders']], indexes: [])
    cache.replace(replaced)

    expect(cache.reload(stale, timeout: 1)).to be(replaced)
    expect(schema_state[:vspace_requests]).to eq(1)
  end

  it 'keeps a schema replaced while a reload was fetching' do
    stale = load_schema
    schema_state[:delay] = 0.2
    reload = Thread.new { cache.reload(stale, timeout: 1) }
    wait_for { schema_state[:vspace_requests] == 2 }
    replaced = Tarantool::Client::Schema.new(version: 1, spaces: [[600, 1, 'users']], indexes: [])
    cache.replace(replaced)

    expect(reload.value).to be(replaced)
    expect(cache.schema).to be(replaced)
  end
end
