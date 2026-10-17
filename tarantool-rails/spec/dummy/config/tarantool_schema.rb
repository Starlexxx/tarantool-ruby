# frozen_string_literal: true

Tarantool::Rails.schema = Tarantool::Schema::Definition.new do
  ensure_space :rails_notes,
               format: [{ name: :id, type: :unsigned }, { name: :body, type: :string }],
               indexes: [{ name: :primary, parts: [:id], sequence: true }]
end
