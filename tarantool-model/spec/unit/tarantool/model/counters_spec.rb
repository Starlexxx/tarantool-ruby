# frozen_string_literal: true

RSpec.describe Tarantool::Model::Counters do
  include_context 'with users'

  let!(:user) { User.create!(id: 1, email: 'a@x', age: 5) }

  before { storage.update(:users, [1], [['+', 'age', 10]]) }

  it 'adds on the server and takes the new value from the response' do
    expect(user.increment!(:age, 2).age).to eq(17)
    expect(storage.get(:users, [1]).attributes[:age]).to eq(17)
  end

  it 'subtracts one by default' do
    expect(user.decrement!(:age).age).to eq(14)
  end

  it 'skips validations and callbacks and keeps other unsaved changes' do
    User.before_save { raise 'callback ran' }
    user.email = nil

    expect(user.increment!(:age)).to have_attributes(age: 16, changes: { 'email' => ['a@x', nil] })
  end

  it 'raises RecordNotFound when the row is gone' do
    storage.delete(:users, [1])

    expect { user.increment!(:age) }.to raise_error(Tarantool::Model::RecordNotFound)
  end
end
