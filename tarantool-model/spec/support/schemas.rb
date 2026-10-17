# frozen_string_literal: true

# Declarations of the spaces the integration servers create: users and accounts in spec/integration/box.lua,
# users with bucket_id in spec/integration/crud_init.lua.
module Schemas
  USERS = {
    format: [{ name: :id, type: :unsigned }, { name: :email, type: :string }, { name: :age, type: :unsigned }],
    indexes: [{ name: :primary, parts: %i[id] }, { name: :email, parts: %i[email] },
              { name: :age, parts: %i[age], unique: false }]
  }.freeze

  LOCKED_USERS = {
    format: [*USERS[:format], { name: :lock_version, type: :unsigned }],
    indexes: USERS[:indexes]
  }.freeze

  ACCOUNTS = {
    format: [{ name: :id, type: :unsigned }, { name: :email, type: :string },
             { name: :balance, type: :decimal, is_nullable: true }, { name: :token, type: :uuid, is_nullable: true },
             { name: :created_at, type: :datetime, is_nullable: true },
             { name: :period, type: :interval, is_nullable: true },
             { name: :avatar, type: :varbinary, is_nullable: true }, { name: :tags, type: :any, is_nullable: true }],
    indexes: [{ name: :primary, parts: %i[id], sequence: true }, { name: :email, parts: %i[email] }]
  }.freeze

  CRUD_USERS = {
    format: [{ name: :id, type: :unsigned }, { name: :bucket_id, type: :unsigned }, { name: :email, type: :string },
             { name: :age, type: :unsigned }],
    indexes: [{ name: :primary, parts: %i[id] }, { name: :bucket_id, parts: %i[bucket_id], unique: false },
              { name: :email, parts: %i[email] }, { name: :age, parts: %i[age], unique: false }]
  }.freeze
end
