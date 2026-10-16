# frozen_string_literal: true

RSpec.describe Tarantool::Model::Transactional do
  include_context 'with users'

  let(:other_storage) { Tarantool::Model::Testing::MemoryStorage.new(users: Schemas::USERS) }

  before do
    stub_const('Member', Class.new(User) { self.space_name = :users })
    Member.storage = other_storage
  end

  it 'commits writes of models sharing the storage and returns the block value' do
    expect(User.transaction(isolation: :read_committed) { User.create!(id: 1, email: 'a@x') && :ok }).to eq(:ok)
    expect(storage.get(:users, [1])).not_to be_nil
  end

  it 'rolls back and re-raises; in-memory records keep their state' do
    user = User.new(id: 1, email: 'a@x')

    expect { User.transaction { user.save! && raise('boom') } }.to raise_error('boom')
    expect([storage.get(:users, [1]), user.persisted?]).to eq([nil, true])
  end

  it 'raises TransactionMismatchError for a write through another storage, before sending anything' do
    expect { User.transaction { Member.create!(id: 2, email: 'b@x') } }
      .to raise_error(Tarantool::Model::TransactionMismatchError)
    expect(other_storage.get(:users, [2])).to be_nil
  end

  it 'checks update! as well' do
    member = Member.create!(id: 3, email: 'c@x')

    expect { User.transaction { member.update!(email: 'd@x') } }
      .to raise_error(Tarantool::Model::TransactionMismatchError)
  end

  it 'checks destroy as well' do
    member = Member.create!(id: 3, email: 'c@x')

    expect { User.transaction { member.destroy } }
      .to raise_error(Tarantool::Model::TransactionMismatchError)
  end

  it 'checks increment! as well' do
    member = Member.create!(id: 3, email: 'c@x')

    expect { User.transaction { member.increment!(:age) } }
      .to raise_error(Tarantool::Model::TransactionMismatchError)
  end

  it 'allows reads through another storage' do
    Member.create!(id: 4, email: 'e@x')

    expect(User.transaction { Member.find(4).id }).to eq(4)
  end
end
