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
  end
end
