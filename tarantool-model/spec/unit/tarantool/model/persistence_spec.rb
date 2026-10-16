# frozen_string_literal: true

RSpec.describe Tarantool::Model::Persistence do
  include_context 'with users'

  describe 'create' do
    it 'inserts a valid record and marks it persisted' do
      user = User.create(id: 1, email: 'a@x')

      expect([user.persisted?, user.changed?, storage.get(:users, [1]).attributes[:email]]).to eq([true, false, 'a@x'])
    end

    it 'propagates the storage error for a primary key that cannot be nil' do
      expect { User.create!(id: nil, email: 'a@x') }.to raise_error(Tarantool::ServerError)
    end

    it 'keeps the tuple of the written row' do
      expect(User.create!(id: 1, email: 'a@x').tuple).to eq([1, 'a@x', 0])
    end

    it 'returns false and sends nothing for an invalid record' do
      expect(User.new(id: 1).save).to be(false)
      expect(storage.get(:users, [1])).to be_nil
    end

    it 'raises RecordInvalid from create!' do
      expect { User.create!(id: 1) }.to raise_error(Tarantool::Model::RecordInvalid, "Email can't be blank")
    end

    it 'raises RecordNotUnique for a duplicate key' do
      User.create!(id: 1, email: 'a@x')

      expect { User.create!(id: 1, email: 'b@x') }.to raise_error(Tarantool::Model::RecordNotUnique)
    end
  end

  describe 'update' do
    let!(:user) { User.create!(id: 1, email: 'a@x', age: 5) }

    before { allow(storage).to receive(:update).and_call_original }

    it 'sends only the changed attributes and applies the changes' do
      user.update!(email: 'b@x')

      expect(storage).to have_received(:update).with('users', [1], [['=', 'email', 'b@x']])
      expect([user.changed?, user.previous_changes['email']]).to eq([false, ['a@x', 'b@x']])
    end

    it 'sends nothing when nothing changed' do
      expect(user.save).to be(true)
      expect(storage).not_to have_received(:update)
    end

    it 'raises ArgumentError when the primary key changes' do
      expect { user.update(id: 2) }.to raise_error(ArgumentError, /primary key/)
    end

    it 'raises RecordNotFound and keeps the changes when the row is gone' do
      storage.delete(:users, [1])

      expect { user.update(email: 'b@x') }.to raise_error(Tarantool::Model::RecordNotFound)
      expect(user.changes).to eq('email' => ['a@x', 'b@x'])
    end
  end

  describe 'callbacks' do
    before do
      log = events
      User.before_validation { log << :before_validation }
      User.before_save { log << :before_save }
      User.before_create { log << :before_create }
      User.after_create { log << :after_create }
      User.before_update { log << :before_update }
      User.after_update { log << :after_update }
      User.after_save { log << :after_save }
    end

    it 'runs validation, save and create callbacks in order' do
      User.create!(id: 1, email: 'a@x')

      expect(events).to eq(%i[before_validation before_save before_create after_create after_save])
    end

    it 'runs validation, save and update callbacks in order' do
      user = User.create!(id: 1, email: 'a@x')
      events.clear

      user.update!(email: 'b@x')

      expect(events).to eq(%i[before_validation before_save before_update after_update after_save])
    end

    it 'returns false from save and raises RecordNotSaved from save! when a before callback aborts' do
      User.before_save { throw :abort }

      expect(User.new(id: 1, email: 'a@x').save).to be(false)
      expect { User.new(id: 2, email: 'b@x').save! }.to raise_error(Tarantool::Model::RecordNotSaved)
    end
  end

  describe 'destroy' do
    let!(:user) { User.create!(id: 1, email: 'a@x') }

    it 'deletes the row, marks the record destroyed and freezes it' do
      expect(user.destroy).to be(user)
      expect([user.destroyed?, user.persisted?, storage.get(:users, [1])]).to eq([true, false, nil])
      expect { user.email = 'b@x' }.to raise_error(FrozenError)
    end

    it 'counts a row that is already gone as destroyed' do
      storage.delete(:users, [1])

      expect(user.destroy.destroyed?).to be(true)
    end

    it 'returns false and leaves the record untouched when a before callback aborts' do
      User.before_destroy { throw :abort }

      expect(user.destroy).to be(false)
      expect([user.destroyed?, user.persisted?, user.frozen?]).to eq([false, true, false])
      expect(storage.get(:users, [1])).not_to be_nil
    end
  end

  describe 'reload' do
    let!(:user) { User.create!(id: 1, email: 'a@x') }

    it 'reads the row again and drops unsaved changes' do
      storage.update(:users, [1], [['=', 'email', 'b@x']])
      user.age = 9

      expect(user.reload).to have_attributes(email: 'b@x', age: 0, changed?: false)
    end

    it 'raises RecordNotFound when the row is gone' do
      storage.delete(:users, [1])

      expect { user.reload }.to raise_error(Tarantool::Model::RecordNotFound) { |error| expect(error.key).to eq([1]) }
    end
  end
end
