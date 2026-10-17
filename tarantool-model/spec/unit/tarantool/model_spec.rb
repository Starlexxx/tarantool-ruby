# frozen_string_literal: true

SEMVER = /\A\d+\.\d+\.\d+\z/

RSpec.describe Tarantool::Model do
  let(:base) do
    Class.new do
      include Tarantool::Model

      attribute :id, :integer
    end
  end

  before { stub_const('User', Class.new(base)) }

  it 'has a version' do
    expect(Tarantool::Model::VERSION).to match(SEMVER)
  end

  describe '.space_name' do
    it 'defaults to the plural model name' do
      expect(User.space_name).to eq('users')
    end

    it 'is inherited once set' do
      User.space_name = :members
      stub_const('Admin', Class.new(User))

      expect(Admin.space_name).to eq(:members)
    end
  end

  describe '.primary_key_names' do
    it 'wraps a single and keeps a composite primary key' do
      expect(User.primary_key_names).to eq([:id])
      User.primary_key = %i[tenant_id id]
      expect(User.primary_key_names).to eq(%i[tenant_id id])
    end
  end

  describe '#to_key and #to_param' do
    before do
      User.primary_key = %i[tenant_id id]
      User.attribute :tenant_id, :integer
    end

    it 'are nil for a new record' do
      expect([User.new(id: 1).to_key, User.new(id: 1).to_param]).to eq([nil, nil])
    end

    it 'join a composite key with a dash for a persisted record' do
      user = User.instantiate(Tarantool::Model::Row.new(attributes: { tenant_id: 7, id: 1 }, tuple: [7, 1]))

      expect([user.to_key, user.to_param]).to eq([[7, 1], '7-1'])
    end
  end

  describe '.verified_storage' do
    let(:storage) do
      Class.new do
        def calls
          @calls ||= []
        end

        def verify(space, **options)
          calls << [space, options]
        end
      end.new
    end

    it 'checks the schema once per storage' do
      User.storage = storage
      2.times { User.verified_storage }

      expect(storage.calls).to eq([['users', { attributes: [:id], primary_key: [:id] }]])
    end

    it 'raises when no storage is set' do
      expect { User.verified_storage }.to raise_error(Tarantool::Model::Error, 'User.storage is not set')
    end

    it 'verifies again when the storage is swapped for a different one' do
      other = storage.class.new
      User.storage = storage
      User.verified_storage
      User.storage = other

      User.verified_storage

      expect(other.calls).to eq([['users', { attributes: [:id], primary_key: [:id] }]])
    end
  end

  describe '.default_storage' do
    let(:storage) { Tarantool::Model::Testing::MemoryStorage.new({ users: Schemas::USERS }) }

    after { described_class.default_storage = nil }

    it 'is used by a model without a storage of its own' do
      described_class.default_storage = storage

      expect(User.storage).to be(storage)
    end

    it 'calls a Proc once on first use and shares the result' do
      calls = 0
      described_class.default_storage = -> { calls += 1 and storage }
      stub_const('Member', Class.new(base))

      expect([User.storage, Member.storage, calls]).to eq([storage, storage, 1])
    end

    it 'keeps a Proc that raised so the next read retries' do
      attempts = 0
      described_class.default_storage = -> { (attempts += 1) == 1 ? raise('not yet') : storage }

      expect { User.storage }.to raise_error('not yet')
      expect(User.storage).to be(storage)
    end

    it 'yields to a storage set on the model' do
      own = Tarantool::Model::Testing::MemoryStorage.new({ users: Schemas::USERS })
      described_class.default_storage = storage
      User.storage = own

      expect(User.storage).to be(own)
    end

    it 'leaves the error for a model without any storage' do
      expect { User.verified_storage }.to raise_error(Tarantool::Model::Error, 'User.storage is not set')
    end
  end
end
