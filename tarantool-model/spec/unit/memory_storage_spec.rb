# frozen_string_literal: true

RSpec.describe MemoryStorage do
  subject(:storage) { described_class.new(users: MemoryStorage::USERS) }

  it_behaves_like 'a model storage'

  it 'assigns the next id to a nil single-field primary key, like a sequence' do
    storage.insert(:users, { id: 4, email: 'a', age: 1 })

    expect(storage.insert(:users, { id: nil, email: 'b', age: 1 }).attributes[:id]).to eq(5)
  end
end
