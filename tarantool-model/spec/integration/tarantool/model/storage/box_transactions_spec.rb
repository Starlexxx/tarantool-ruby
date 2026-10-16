# frozen_string_literal: true

RSpec.describe Tarantool::Model::Storage::Box, :integration do
  let(:uri) { ENV.fetch('TARANTOOL_MODEL_URI', 'tcp://app:secret@localhost:3321') }
  let(:primary_client) { Tarantool::Client.new(uri) }
  let(:observer_client) { Tarantool::Client.new(uri) }
  let(:primary_storage) { described_class.new(primary_client) }
  let(:observer_storage) { described_class.new(observer_client) }

  before do
    primary_client.eval('box.space.users:truncate()')
    stub_const('User', Class.new do
      include Tarantool::Model

      attribute :id, :integer
      attribute :email, :string
      attribute :age, :integer, default: 0
    end)
    User.storage = primary_storage
    stub_const('Member', Class.new(User) { self.space_name = :users })
    Member.storage = observer_storage
  end

  after do
    primary_client.close
    observer_client.close
  end

  it 'commits: the row is visible through the second client after the transaction' do
    User.transaction(isolation: :read_committed) { User.create!(id: 1, email: 'a@x') }

    expect(observer_storage.get(:users, [1])).not_to be_nil
  end

  it 'rolls back: the row is absent through the second client and the error propagates' do
    expect { User.transaction { User.create!(id: 2, email: 'b@x') && raise('boom') } }.to raise_error('boom')

    expect(observer_storage.get(:users, [2])).to be_nil
  end

  it 'is invisible to the second client while the block runs (MVCC)' do
    seen_inside = nil
    User.transaction(isolation: :read_committed) do
      User.create!(id: 3, email: 'c@x')
      seen_inside = observer_storage.get(:users, [3])
    end

    expect(seen_inside).to be_nil
  end

  it 'raises TransactionMismatchError for a write through another storage; the row is absent afterwards' do
    expect { User.transaction { Member.create!(id: 4, email: 'd@x') } }
      .to raise_error(Tarantool::Model::TransactionMismatchError)

    expect(observer_storage.get(:users, [4])).to be_nil
  end

  it 'raises TransactionError for a nested transaction' do
    expect { User.transaction { User.transaction { nil } } }.to raise_error(Tarantool::TransactionError)
  end

  it 'runs find_each and space_info reads inside a transaction' do
    User.create!(id: 5, email: 'e@x')
    User.create!(id: 6, email: 'f@x')

    ids = User.transaction(isolation: :read_committed) do
      User.all.find_each(batch_size: 1).map(&:id)
    end

    expect(ids).to include(5, 6)
  end

  it 'runs a transaction over a Pool with read and write modes' do
    pool = Tarantool::Client::Pool.new([uri])
    box = described_class.new(pool, read: { mode: :any, timeout: 1 }, write: { mode: :rw, timeout: 1 })

    box.transaction(isolation: :read_committed) do
      box.insert(:users, { id: 7, email: 'g@x', age: 0 })
    end

    expect(observer_storage.get(:users, [7])).not_to be_nil
  ensure
    pool&.close
  end
end
