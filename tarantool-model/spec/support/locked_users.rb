# frozen_string_literal: true

RSpec.shared_context 'with locked users' do
  let(:storage) { Tarantool::Model::Testing::MemoryStorage.new({ users: Schemas::LOCKED_USERS }) }

  before do
    stub_const('LockedUser', Class.new do
      include Tarantool::Model

      self.space_name = 'users'

      attribute :id, :integer
      attribute :email, :string
      attribute :age, :integer, default: 0
      attribute :lock_version, :integer, default: 0
    end)
    LockedUser.storage = storage
  end
end
