# frozen_string_literal: true

RSpec.describe Tarantool::Model::Storage::Crud do
  subject(:storage) { described_class.new(crud) }

  let(:crud) { instance_double(Tarantool::Crud::Client, space: users) }
  let(:users) { instance_double(Tarantool::Crud::Space) }
  let(:row) { { id: 1, bucket_id: 7, email: 'a', age: 3 } }
  let(:result) do
    Tarantool::Crud::Result.new(metadata: %w[id bucket_id email age].map { |name| { name: } },
                                tuples: [[1, 7, 'a', 3], [2, 9, 'b', 3]])
  end

  it 'raises a clear error when tarantool-crud is not loaded' do
    hide_const('Tarantool::Crud')

    expect { described_class.new(Object.new) }
      .to raise_error(Tarantool::Model::Error, "tarantool-crud is not loaded; require 'tarantool/crud'")
  end

  it 'returns nil rows without a tuple for get, update, and nil-returning delete' do
    allow(users).to receive_messages(get: row, insert: row, update: nil, delete: row)

    expect(storage.get(:users, [1])).to eq(Tarantool::Model::Row.new(attributes: row, tuple: nil))
    expect([storage.update(:users, [1], []), storage.delete(:users, [1]).tuple]).to eq([nil, nil])
  end

  it 'wraps a returned hash in a Row with nil tuple for insert' do
    allow(users).to receive(:insert).and_return(row)

    expect(storage.insert(:users, row).tuple).to be_nil
  end

  it 'inserts the attribute Hash, which crud sends as an object' do
    allow(users).to receive(:insert).and_return(row)
    storage.insert(:users, { id: 1, email: 'a', age: 3 })

    expect(users).to have_received(:insert).with({ id: 1, email: 'a', age: 3 })
  end

  it 'maps an index condition to crud conditions with first and after' do
    allow(users).to receive(:select).and_return(result)
    rows = storage.select(:users, index: :age, key: [3], iterator: :ge, limit: 2, after: [0, 1, 'z', 3])

    expect(users).to have_received(:select).with([['>=', 'age', [3]]], first: 2, after: [0, 1, 'z', 3])
    expect(rows.map(&:tuple)).to eq(result.tuples)
  end

  it 'uses the primary index name for index nil and no conditions for :all' do
    allow(users).to receive(:select).and_return(result)
    storage.select(:users, index: nil, key: [1], iterator: :lt, limit: nil, after: nil)
    storage.select(:users, index: nil, key: [], iterator: :all, limit: nil, after: nil)

    expect(users).to have_received(:select).with([['<', 'primary', [1]]]).ordered
    expect(users).to have_received(:select).with(nil).ordered
  end

  it 'takes another primary index name' do
    allow(users).to receive(:count).and_return(5)

    expect(described_class.new(crud, primary_index: :pk).count(:users, index: nil, key: [1], iterator: :eq)).to eq(5)
    expect(users).to have_received(:count).with([['==', 'pk', [1]]])
  end

  it 'rejects iterators crud has no condition for' do
    expect { storage.count(:users, index: :age, key: [1], iterator: :req) }.to raise_error(ArgumentError, /req/)
  end

  it 'raises RecordNotUnique for a duplicate key insert' do
    allow(users).to receive(:insert).and_raise(Tarantool::Crud::InsertError, 'Failed to insert: Duplicate key exists')

    expect { storage.insert(:users, row) }.to raise_error(Tarantool::Model::RecordNotUnique)
  end

  it 'passes other crud errors through' do
    allow(users).to receive(:update).and_raise(Tarantool::Crud::UpdateError, "Field 'zzz' was not found")

    expect { storage.update(:users, [1], []) }.to raise_error(Tarantool::Crud::UpdateError)
  end

  it 'does not open transactions' do
    expect { storage.transaction { nil } }.to raise_error(Tarantool::Model::NotSupportedError)
  end

  it 'does not check the schema' do
    expect(storage.verify(:users, attributes: [:x], primary_key: [:id])).to be_nil
  end
end
