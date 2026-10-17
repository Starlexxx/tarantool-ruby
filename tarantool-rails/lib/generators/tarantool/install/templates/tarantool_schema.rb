# frozen_string_literal: true

# Applied by `rails tarantool:schema:apply`; `rails g tarantool:model` adds spaces here.
Tarantool::Rails.schema = Tarantool::Schema::Definition.new do
  # ensure_space :users,
  #              format: [{ name: :id, type: :unsigned }, { name: :email, type: :string }],
  #              indexes: [{ name: :primary, parts: [:id], sequence: true }, { name: :email, parts: [:email] }]
end
