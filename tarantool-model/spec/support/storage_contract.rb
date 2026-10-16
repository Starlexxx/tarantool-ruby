# frozen_string_literal: true

# Needs `storage` and an empty `users` space (id, email, age; indexes primary, email, age).
RSpec.shared_examples 'a model storage' do |count: true|
  let(:people) do
    [[1, 30], [2, 20], [3, 30], [4, 10], [5, 30], [6, 20]].map { |id, age| { id:, email: "u#{id}@x", age: } }
  end

  def ids(rows) = rows.map { |row| row.attributes[:id] }

  def select(index: :age, key: [], iterator: :all, limit: nil, after: nil)
    storage.select(:users, index:, key:, iterator:, limit:, after:)
  end

  before { people.each { |person| storage.insert(:users, person) } }

  it 'inserts and gets a row' do
    expect(storage.insert(:users, { id: 7, email: 'u7@x', age: 1 }).attributes).to include(id: 7, age: 1)
    expect(storage.get(:users, [7]).attributes).to include(id: 7, email: 'u7@x', age: 1)
  end

  it 'returns nil for a missing key' do
    expect([storage.get(:users, [99]), storage.update(:users, [99], [['=', 'age', 1]]), storage.delete(:users, [99])])
      .to eq([nil, nil, nil])
  end

  it 'raises RecordNotUnique for a duplicate primary key' do
    expect { storage.insert(:users, { id: 1, email: 'other@x', age: 1 }) }
      .to raise_error(Tarantool::Model::RecordNotUnique)
  end

  it 'updates fields by name and returns the new row' do
    row = storage.update(:users, [1], [['=', 'email', 'new@x'], ['+', 'age', 2]])

    expect(row.attributes).to include(id: 1, email: 'new@x', age: 32)
  end

  it 'deletes a row and returns it' do
    expect(storage.delete(:users, [1]).attributes).to include(id: 1)
    expect(storage.get(:users, [1])).to be_nil
  end

  it 'selects all rows of the primary index with their tuples' do
    rows = select(index: nil)

    expect(ids(rows)).to eq([1, 2, 3, 4, 5, 6])
    expect(rows.map(&:tuple)).to all(be_an(Array))
  end

  it 'selects equal keys of a non-unique index in primary key order' do
    expect(ids(select(key: [30], iterator: :eq))).to eq([1, 3, 5])
  end

  it 'selects :ge with a limit' do
    expect(ids(select(key: [20], iterator: :ge, limit: 2))).to eq([2, 6])
  end

  it 'selects :lt in descending order' do
    expect(ids(select(key: [30], iterator: :lt))).to eq([6, 2, 4])
  end

  it 'selects :le in descending order' do
    expect(ids(select(key: [20], iterator: :le))).to eq([6, 2, 4])
  end

  it 'selects :gt' do
    expect(ids(select(key: [20], iterator: :gt))).to eq([1, 3, 5])
  end

  it 'combines a limit with after' do
    first = select(key: [20], iterator: :ge).first

    expect(ids(select(key: [20], iterator: :ge, after: first.tuple, limit: 2))).to eq([6, 1])
  end

  it 'continues after a tuple on a non-unique index' do
    first = select(key: [20], iterator: :ge, limit: 2)

    expect(ids(select(key: [20], iterator: :ge, after: first.last.tuple))).to eq([1, 3, 5])
  end

  it 'continues after a tuple in descending order' do
    first = select(key: [30], iterator: :lt, limit: 1)

    expect(ids(select(key: [30], iterator: :lt, after: first.last.tuple))).to eq([2, 4])
  end

  if count
    it 'counts every match of the index condition' do
      expect(storage.count(:users, index: :age, key: [20], iterator: :ge)).to eq(5)
    end
  end
end
