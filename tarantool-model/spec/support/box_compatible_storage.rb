# frozen_string_literal: true

# The Storage::Box contract beyond 'a model storage'. Needs `storage` and empty `users` and `accounts` spaces as in
# spec/integration/box.lua.
RSpec.shared_examples 'a box-compatible storage' do
  def server_error(code)
    an_instance_of(Tarantool::ServerError).and(having_attributes(code:))
  end

  before { storage.insert(:users, { id: 1, email: 'a@x', age: 1 }) }

  it 'raises RecordNotUnique for a duplicate unique secondary key on insert and update' do
    storage.insert(:users, { id: 2, email: 'b@x', age: 1 })

    expect { storage.insert(:users, { id: 3, email: 'a@x', age: 1 }) }.to raise_error(Tarantool::Model::RecordNotUnique)
    expect { storage.update(:users, [2], [['=', 'email', 'a@x']]) }.to raise_error(Tarantool::Model::RecordNotUnique)
  end

  it 'raises ServerError 23 for nil in a non-nullable field' do
    expect { storage.insert(:users, { id: 2, email: 'b@x' }) }.to raise_error(server_error(23))
    expect { storage.update(:users, [1], [['=', 'age', nil]]) }.to raise_error(server_error(23))
  end

  it 'raises ServerError 94 for a changed primary key and accepts the same value' do
    expect { storage.update(:users, [1], [['=', 'id', 5]]) }.to raise_error(server_error(94))
    expect(storage.update(:users, [1], [['=', 'id', 1]]).attributes).to include(id: 1)
  end

  it 'raises ServerError 26 for arithmetic on a string and 201 for an unknown field' do
    expect { storage.update(:users, [1], [['+', 'email', 1]]) }.to raise_error(server_error(26))
    expect { storage.update(:users, [1], [['=', 'nope', 1]]) }.to raise_error(server_error(201))
  end

  it 'raises ServerError 19 for an update or delete whose key is not the whole primary key' do
    message = 'Invalid key part count in an exact match (expected 1, got 2)'

    expect { storage.update(:users, [1, 2], [['=', 'age', 2]]) }
      .to raise_error(server_error(19).and(having_attributes(message:)))
    expect { storage.delete(:users, []) }.to raise_error(server_error(19), /got 0/)
  end

  it 'raises Tarantool::SchemaError for an unknown space or index' do
    expect { storage.get(:nope, [1]) }.to raise_error(Tarantool::SchemaError)
    expect { storage.select(:users, index: :nope, key: [], iterator: :all, limit: nil, after: nil) }
      .to raise_error(Tarantool::SchemaError)
  end

  it 'reads iterator :all with a key on a tree index like :ge' do
    [[2, 5], [3, 9]].each { |id, age| storage.insert(:users, { id:, email: "u#{id}", age: }) }

    rows = storage.select(:users, index: :age, key: [5], iterator: :all, limit: nil, after: nil)

    expect(rows.map { |row| row.attributes[:id] }).to eq([2, 3])
  end

  it 'raises SchemaMismatchError from verify' do
    expect { storage.verify(:users, attributes: %i[id phone], primary_key: %i[id]) }
      .to raise_error(Tarantool::Model::SchemaMismatchError, /phone/)
    expect { storage.verify(:users, attributes: %i[id], primary_key: %i[email]) }
      .to raise_error(Tarantool::Model::SchemaMismatchError)
  end

  it 'takes nil primary keys from the sequence and moves it past explicit values' do
    first = storage.insert(:accounts, { id: nil, email: 's1' }).attributes[:id]
    storage.insert(:accounts, { id: first + 10, email: 's2' })

    expect(storage.insert(:accounts, { id: nil, email: 's3' }).attributes[:id]).to eq(first + 11)
  end

  it 'commits a transaction and rolls it back when the block raises' do
    storage.transaction { storage.insert(:users, { id: 2, email: 'b@x', age: 1 }) }
    expect { storage.transaction { storage.delete(:users, [2]) && raise('boom') } }.to raise_error('boom')

    expect(storage.get(:users, [2]).attributes).to include(id: 2)
  end

  it 'raises TransactionError for a nested transaction' do
    expect { storage.transaction { storage.transaction { nil } } }.to raise_error(Tarantool::TransactionError)
  end
end
