# frozen_string_literal: true

RSpec.describe Tarantool::Model::Locking do
  describe '.locking_enabled?' do
    include_context 'with users'

    it 'is off for a model without the locking attribute' do
      expect([User.locking_column, User.locking_enabled?]).to eq([:lock_version, false])
    end

    it 'saves such a model as before' do
      user = User.create!(id: 1, email: 'a@x')
      user.update!(email: 'b@x')

      expect(storage.get(:users, [1]).attributes).to include(email: 'b@x')
    end
  end

  context 'with the locking attribute' do
    include_context 'with locked users'

    it 'is on by default and off with locking_column = nil' do
      enabled = LockedUser.locking_enabled?
      LockedUser.locking_column = nil

      expect([enabled, LockedUser.locking_enabled?]).to eq([true, false])
    end

    describe 'create' do
      it 'stores version 0 for a nil version' do
        user = LockedUser.create!(id: 1, email: 'a@x', lock_version: nil)

        expect([user.lock_version, storage.get(:users, [1]).attributes[:lock_version]]).to eq([0, 0])
      end

      it 'keeps an explicit version' do
        expect(LockedUser.create!(id: 1, email: 'a@x', lock_version: 4).lock_version).to eq(4)
      end
    end

    describe 'update' do
      let!(:user) { LockedUser.create!(id: 1, email: 'a@x') }

      before do
        allow(storage).to receive(:update).and_call_original
        allow(storage).to receive(:transaction).and_call_original
      end

      it 'sends the changes with the bumped version and refreshes it' do
        user.update!(email: 'b@x')

        expect(storage).to have_received(:update).with('users', [1], [['=', 'email', 'b@x'], ['=', 'lock_version', 1]])
        expect([user.lock_version, user.changed?]).to eq([1, false])
      end

      it 'bumps again on the next update' do
        user.update!(email: 'b@x')
        user.update!(email: 'c@x')

        expect(storage).to have_received(:update).with('users', [1], [['=', 'email', 'c@x'], ['=', 'lock_version', 2]])
      end

      it 'treats a nil stored version as 0' do
        format = [*Schemas::USERS[:format], { name: :lock_version, type: :unsigned, is_nullable: true }]
        schema = Schemas::LOCKED_USERS.merge(format:)
        LockedUser.storage = Tarantool::Model::Testing::MemoryStorage.new({ users: schema })
        LockedUser.storage.insert(:users, { id: 2, email: 'n@x', age: 0, lock_version: nil })

        user = LockedUser.find(2)
        user.update!(email: 'b@x')

        expect(user.lock_version).to eq(1)
      end

      it 'raises StaleObjectError and keeps the changes when the row changed underneath' do
        storage.update(:users, [1], [['=', 'lock_version', 5]])

        expect { user.update!(email: 'b@x') }
          .to raise_error(Tarantool::Model::StaleObjectError) { |error| expect(error.attempted_action).to eq(:update) }
        expect([user.changes, storage.get(:users, [1]).attributes[:email]])
          .to eq([{ 'email' => ['a@x', 'b@x'] }, 'a@x'])
      end

      it 'compares the version assigned to the record, as from a form' do
        user.update!(email: 'b@x')
        user.lock_version = 0

        expect { user.update!(email: 'c@x') }.to raise_error(Tarantool::Model::StaleObjectError)
      end

      it 'raises RecordNotFound when the row is gone' do
        storage.delete(:users, [1])

        expect { user.update!(email: 'b@x') }.to raise_error(Tarantool::Model::RecordNotFound)
      end

      it 'sends nothing and opens no transaction when nothing changed' do
        expect(user.save).to be(true)
        expect(storage).not_to have_received(:update)
        expect(storage).not_to have_received(:transaction)
      end

      it 'sends nothing when only the version changed' do
        user.lock_version = 3

        expect(user.save).to be(true)
        expect(storage).not_to have_received(:update)
      end

      it 'checks and updates inside the transaction that is already open' do
        LockedUser.transaction { user.update!(email: 'b@x') }

        expect(storage).to have_received(:transaction).once
        expect(user.lock_version).to eq(1)
      end

      it 'opens a transaction of its own otherwise' do
        user.update!(email: 'b@x')

        expect(storage).to have_received(:transaction).once
      end

      it 'maps a transaction conflict to StaleObjectError' do
        allow(storage).to receive(:update).and_raise(Tarantool::ServerError.new('aborted by conflict', code: 97))

        expect { user.update!(email: 'b@x') }.to raise_error(Tarantool::Model::StaleObjectError)
      end

      it 'leaves the version alone on increment!' do
        user.increment!(:age)

        expect([user.lock_version, storage.get(:users, [1]).attributes[:lock_version]]).to eq([0, 0])
      end
    end

    describe 'destroy' do
      let!(:user) { LockedUser.create!(id: 1, email: 'a@x') }

      it 'deletes a current record' do
        expect(user.destroy).to be(user)
        expect([user.destroyed?, storage.get(:users, [1])]).to eq([true, nil])
      end

      it 'raises StaleObjectError and leaves the record and the row alone when stale' do
        storage.update(:users, [1], [['=', 'lock_version', 5]])

        expect { user.destroy }
          .to raise_error(Tarantool::Model::StaleObjectError) { |error| expect(error.attempted_action).to eq(:destroy) }
        expect([user.frozen?, user.destroyed?, storage.get(:users, [1]).nil?]).to eq([false, false, false])
      end

      it 'counts a row that is already gone as destroyed' do
        storage.delete(:users, [1])

        expect(user.destroy.destroyed?).to be(true)
      end
    end
  end

  context 'with a storage without transactions' do
    include_context 'with locked users'

    let(:storage) do
      Tarantool::Model::Testing::MemoryStorage.new({ users: Schemas::LOCKED_USERS }, behaves_like: :crud)
    end
    let!(:user) { LockedUser.create!(id: 1, email: 'a@x') }

    before { allow(storage).to receive(:transaction).and_call_original }

    it 'bumps the version without a transaction' do
      user.update!(email: 'b@x')

      expect([user.lock_version, storage.get(:users, [1]).attributes[:lock_version]]).to eq([1, 1])
      expect(storage).not_to have_received(:transaction)
    end

    it 'still raises StaleObjectError for a stale record' do
      storage.update(:users, [1], [['=', 'lock_version', 5]])

      expect { user.update!(email: 'b@x') }.to raise_error(Tarantool::Model::StaleObjectError)
      expect { user.destroy }.to raise_error(Tarantool::Model::StaleObjectError)
    end
  end
end
