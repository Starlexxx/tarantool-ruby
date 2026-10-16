# frozen_string_literal: true

RSpec.describe Tarantool::Client, :integration do
  subject(:client) { described_class.new(uri) }

  let(:uri) { ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301') }
  let(:row) { Tarantool::Client::Row }

  before do
    client.eval(<<~LUA)
      if box.space.t2h_users then box.space.t2h_users:drop() end
      local s = box.schema.space.create('t2h_users', {format = {
        {name = 'id', type = 'unsigned'}, {name = 'name', type = 'string'},
        {name = 'age', type = 'unsigned', is_nullable = true}}})
      s:create_index('primary', {parts = {'id'}})
    LUA
  end

  after do
    client.eval('if box.space.t2h_users then box.space.t2h_users:drop() end')
    client.close
  end

  it 'inserts a Hash and returns Hashes' do
    expect(client.insert(:t2h_users, { name: 'a', 'id' => 1 }, as: :hash)).to eq(id: 1, name: 'a', age: nil)
    expect(client.select(:t2h_users, 1, as: :hash)).to eq([{ id: 1, name: 'a', age: nil }])
  end

  it 'returns the raw tuple with its attributes as a row' do
    client.insert(:t2h_users, [1, 'a'])

    expect(client.select(:t2h_users, 1, as: :row))
      .to eq([row.new(tuple: [1, 'a'], attributes: { id: 1, name: 'a', age: nil })])
  end

  it 'replaces a Hash, then updates and deletes with Hash results' do
    client.replace(:t2h_users, { id: 1, name: 'a' })

    expect(client.update(:t2h_users, 1, [['=', 'age', 5]], as: :hash)).to eq(id: 1, name: 'a', age: 5)
    expect(client.delete(:t2h_users, 1, as: :hash)).to eq(id: 1, name: 'a', age: 5)
  end

  it 'upserts a Hash' do
    client.upsert(:t2h_users, { id: 1, name: 'a', age: 1 }, [['+', 'age', 1]])

    expect(client.select(:t2h_users, 1)).to eq([[1, 'a', 1]])
  end

  it 'keys fields beyond the format by position' do
    client.insert(:t2h_users, [1, 'a', 2, 'extra'])

    expect(client.select(:t2h_users, 1, as: :hash)).to eq([{ id: 1, name: 'a', age: 2, 3 => 'extra' }])
  end

  it 'converts by the format for numeric space and index ids' do
    client.insert(:t2h_users, [1, 'a'])

    expect(client.select(client.space_info(:t2h_users).id, 1, index: 0, as: :hash))
      .to eq([{ id: 1, name: 'a', age: nil }])
  end

  it 'rejects an unknown key without sending' do
    expect { client.insert(:t2h_users, { id: 1, phone: 'x' }) }.to raise_error(ArgumentError, /phone/)
    expect(client.select(:t2h_users)).to eq([])
  end

  it 'rebuilds a Hash tuple by the new format after an alter inserts a field in the middle' do
    client.space_info(:t2h_users)
    client.eval(<<~LUA)
      box.space.t2h_users:format({{name = 'id', type = 'unsigned'},
        {name = 'nick', type = 'string', is_nullable = true}, {name = 'name', type = 'string'},
        {name = 'age', type = 'unsigned', is_nullable = true}})
    LUA

    expect(client.insert(:t2h_users, { id: 1, name: 'a' }, as: :hash)).to eq(id: 1, nick: nil, name: 'a', age: nil)
    expect(client.select(:t2h_users, 1)).to eq([[1, nil, 'a', nil]])
  end

  it 'inserts a Hash with a field added to the format after the schema was loaded' do
    client.space_info(:t2h_users)
    client.eval(<<~LUA)
      box.space.t2h_users:format({{name = 'id', type = 'unsigned'}, {name = 'name', type = 'string'},
        {name = 'age', type = 'unsigned', is_nullable = true}, {name = 'nick', type = 'string', is_nullable = true}})
    LUA

    expect(client.insert(:t2h_users, { id: 1, name: 'a', nick: 'n' }))
      .to eq([1, 'a', nil, 'n'])
  end

  it 'converts inside a transaction' do
    rows = client.transaction do |tx|
      tx.insert(:t2h_users, { id: 1, name: 'a' })
      tx.select(:t2h_users, 1, as: :row)
    end

    expect(rows.map(&:attributes)).to eq([{ id: 1, name: 'a', age: nil }])
  end

  it 'converts through a Pool' do
    pool = Tarantool::Client::Pool.new([uri])
    pool.insert(:t2h_users, { id: 1, name: 'a' }, mode: :rw)

    expect(pool.select(:t2h_users, 1, mode: :any, as: :hash)).to eq([{ id: 1, name: 'a', age: nil }])
  ensure
    pool&.close
  end
end
