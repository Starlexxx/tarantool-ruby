# frozen_string_literal: true

RSpec.describe Tarantool::Model::Relation do
  include_context 'with users'

  before do
    [[1, 30], [2, 20], [3, 30], [4, 10], [5, 30], [6, 20]].each { |id, age| User.create!(id:, email: "u#{id}@x", age:) }
  end

  def ids(relation) = relation.map(&:id)

  it 'filters by one index condition with :eq by default' do
    expect(ids(User.where(index: :age, key: 30))).to eq([1, 3, 5])
  end

  it 'gives descending order for :lt' do
    expect(ids(User.where(index: :age, key: 30, iterator: :lt))).to eq([6, 2, 4])
  end

  it 'is immutable: limit and after return new relations' do
    relation = User.where(index: :age, key: 20, iterator: :ge)
    first_page = relation.limit(2)

    expect([ids(first_page), ids(relation.after(first_page.to_a.last)), ids(relation)])
      .to eq([[2, 6], [1, 3, 5], [2, 6, 1, 3, 5]])
  end

  it 'runs the query on every enumeration' do
    relation = User.all
    relation.to_a
    User.create!(id: 7, email: 'u7@x')

    expect(relation.count).to eq(7)
  end

  it 'rejects a second where' do
    expect { User.where(index: :age, key: 1).where(index: :email, key: 'a') }.to raise_error(ArgumentError, /one index/)
  end

  it 'rejects after a record without a tuple' do
    expect { User.all.after(User.new(id: 1)) }.to raise_error(ArgumentError, /tuple/)
  end

  it 'takes the first record with limit 1' do
    allow(storage).to receive(:select).and_call_original

    expect(User.where(index: :age, key: 30).first.id).to eq(1)
    expect(storage).to have_received(:select).with('users', hash_including(limit: 1))
  end

  it 'counts every match, ignoring limit and after' do
    expect(User.where(index: :age, key: 20, iterator: :ge).limit(1).count).to eq(5)
  end

  it 'enumerates with a block instead of counting in storage' do
    expect(User.all.count { |user| user.age > 20 }).to eq(3)
  end

  it 'enumerates with an argument instead of counting in storage' do
    allow(storage).to receive(:count).and_call_original

    User.all.count(User.new)

    expect(storage).not_to have_received(:count)
  end

  it 'walks every record in batches with find_each' do
    allow(storage).to receive(:select).and_call_original

    expect(User.where(index: :age, key: 20, iterator: :ge).find_each(batch_size: 2).map(&:id)).to eq([2, 6, 1, 3, 5])
    expect(storage).to have_received(:select).exactly(3).times
  end
end
