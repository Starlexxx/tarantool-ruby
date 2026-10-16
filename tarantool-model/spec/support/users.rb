# frozen_string_literal: true

RSpec.shared_context 'with users' do
  let(:storage) { Tarantool::Model::Testing::MemoryStorage.new({ users: Schemas::USERS }) }
  let(:events) { [] }

  before do
    stub_const('User', Class.new do
      include Tarantool::Model

      attribute :id, :integer
      attribute :email, :string
      attribute :age, :integer, default: 0
      validates :email, presence: true
    end)
    User.storage = storage
  end
end
