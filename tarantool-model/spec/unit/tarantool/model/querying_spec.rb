# frozen_string_literal: true

RSpec.describe Tarantool::Model::Querying do
  include_context 'with users'

  before do
    [[1, 30], [2, 20], [3, 30]].each { |id, age| User.create!(id:, email: "u#{id}@x", age:) }
  end

  it 'finds a record by primary key, clean and persisted' do
    expect(User.find(2)).to have_attributes(id: 2, age: 20, persisted?: true, changed?: false)
  end

  it 'finds by a composite key given as an Array' do
    expect(User.find([3]).id).to eq(3)
  end

  it 'raises RecordNotFound with model and key' do
    expect { User.find(9) }.to raise_error(Tarantool::Model::RecordNotFound) do |error|
      expect([error.model, error.key]).to eq([User, [9]])
    end
  end

  it 'finds the first match of an index or nil' do
    expect([User.find_by(index: :age, key: 30).id, User.find_by(index: :age, key: 99)]).to eq([1, nil])
  end

  it 'lists all records in primary key order and counts them' do
    expect([User.all.map(&:id), User.count]).to eq([[1, 2, 3], 3])
  end
end
