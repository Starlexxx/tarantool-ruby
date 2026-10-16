# frozen_string_literal: true

RSpec.describe MemoryStorage do
  subject(:storage) { described_class.new(users: MemoryStorage::USERS) }

  it_behaves_like 'a model storage'

  it 'assigns the next id to a nil single-field primary key, like a sequence' do
    storage.insert(:users, { id: 4, email: 'a', age: 1 })

    expect(storage.insert(:users, { id: nil, email: 'b', age: 1 }).attributes[:id]).to eq(5)
  end

  describe '#transaction' do
    it 'returns the block value and keeps the writes' do
      result = storage.transaction { storage.insert(:users, { id: 1, email: 'a', age: 1 }) && :done }

      expect([result, storage.get(:users, [1])&.attributes&.fetch(:id)]).to eq([:done, 1])
    end

    it 'rolls back and re-raises when the block raises' do
      expect { storage.transaction { storage.insert(:users, { id: 1, email: 'a', age: 1 }) && raise('boom') } }
        .to raise_error('boom')
      expect(storage.get(:users, [1])).to be_nil
    end

    it 'rejects a nested transaction' do
      expect { storage.transaction { storage.transaction { nil } } }.to raise_error(Tarantool::TransactionError)
    end
  end
end
