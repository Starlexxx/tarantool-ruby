# tarantool-model

ActiveModel-based models for Tarantool 2.11+ and 3.x spaces. Provides attributes, validations, callbacks,
dirty tracking, JSON serialization, and index-based queries with keyset pagination. This is not ActiveRecord:
there is no schema migration, no associations, and no query builder. Storage is `Storage::Box` over
`tarantool-client` or `Storage::Crud` over `tarantool/crud`.

## Installation

Requirements: Ruby >= 3.2, Tarantool 2.11+ or 3.x.

```ruby
gem 'tarantool-model'
```

```ruby
require 'tarantool/model'
```

## Declaring a model

```ruby
pool = Tarantool::Client::Pool.new(['tcp://app:secret@db1:3301', 'tcp://app:secret@db2:3301'])

module ApplicationModel
  def self.included(base)
    base.include Tarantool::Model
    base.storage = Tarantool::Model::Storage::Box.new(
      pool,
      read:  { mode: :prefer_ro },
      write: { mode: :rw }
    )
  end
end

class User
  include ApplicationModel

  attribute :id,    :integer
  attribute :email, :string
  attribute :age,   :integer, default: 0

  validates :email, presence: true
end
```

`Storage::Box` passes its `read:`/`write:` options verbatim to the client's read and write requests. The `Pool`
routing `mode:` (symbols like `:prefer_ro`, `:rw`; requires a `Pool` as transport) is one example; `timeout:` works
too. `Storage::Crud` takes no `read:`/`write:`: crud defaults are set on `Tarantool::Crud::Client.new(..., read:,
write:)` and use crud's own options (strings: `mode: 'read'`).

Attribute names must match the space format field names exactly. `space_name` defaults to the plural model
name; set it explicitly with `User.space_name = :members`. The primary key defaults to `:id`; set a composite
key with `User.primary_key = %i[tenant_id id]`.

On the first operation the storage checks that every declared attribute exists in the space format and that
the primary key matches index 0. A mismatch raises `SchemaMismatchError`.

## Types

| Attribute type | Ruby class |
|---|---|
| `:integer` | `Integer` |
| `:string` | `String` |
| `:decimal` | `BigDecimal` |
| `:datetime` | `Time` |
| `:boolean` | `true` / `false` |
| `Types::UUID.new` | `Tarantool::Client::UUID` |
| `Types::Interval.new` | `Tarantool::Client::Interval` |
| `Types::Binary.new` | `String` with `Encoding::BINARY` |

Custom types are passed as objects, not registered globally in `ActiveModel::Type`. A malformed UUID string
casts to `nil`. In-place mutation of a Hash or Array value is not tracked as a change — reassign to mark dirty.

```ruby
attribute :token,      Tarantool::Model::Types::UUID.new
attribute :period,     Tarantool::Model::Types::Interval.new
attribute :avatar,     Tarantool::Model::Types::Binary.new
```

## Persistence

```ruby
user = User.new(id: 1, email: 'a@b.c', age: 20)
user.save       # => true / false (runs validations)
user.save!      # raises RecordInvalid / RecordNotSaved

user = User.create(id: 2, email: 'b@c.d')
User.create!(id: 3, email: 'c@d.e')

user.update(age: 21)    # assign + save
user.update!(age: 21)
user.reload             # re-reads from storage, discards unsaved changes
user.destroy            # returns self (frozen) or false when a before_destroy callback aborts
```

Only changed attributes are sent on update. Attributes are refreshed from the row the storage returns after
every write, so server-side sequences and defaults appear immediately. The primary key cannot change on a
persisted record.

When the row is gone before an update or reload, `RecordNotFound` is raised. When a `before_*` callback
throws `:abort`, `save` returns `false` and `save!` raises `RecordNotSaved`.

Callbacks: `before_validation`, `after_validation`, `before_save`, `around_save`, `after_save`,
`before_create`, `around_create`, `after_create`, `before_update`, `around_update`, `after_update`,
`before_destroy`, `around_destroy`, `after_destroy`.

### Counters

```ruby
user.increment!(:age)       # adds 1 on the server
user.increment!(:age, 5)
user.decrement!(:age)
```

Counters skip validations and callbacks. Only the counter attribute and the raw tuple are refreshed from the
response; other unsaved changes on the record survive. Raises `RecordNotFound` if the row is gone.

## Querying

```ruby
User.find(1)                                         # by primary key, raises RecordNotFound
User.find([tenant_id, id])                           # composite key as Array
User.find_by(index: :email, key: 'a@b.c')            # first match or nil

User.all                                             # Relation over the primary index
User.where(index: :age, key: 20, iterator: :ge)      # one index condition
     .limit(50)
     .after(last_record)                             # keyset pagination, continues after a tuple
     .to_a                                           # Array of model instances
User.where(index: :age, key: 20).first               # limit(1).to_a.first

User.find_each(batch_size: 200) { |user| ... }       # walks in pages, returns Enumerator without block
```

A `Relation` is `Enumerable` and re-runs the query on every enumeration. `limit` and `after` return new
immutable relations. Only one `where` per relation is allowed.

Index order is ascending by default. `:lt` and `:le` iterators give descending order, with ties broken by
primary key descending.

**A relation without `limit` selects every matching row in one request.** Use `find_each` for large result
sets, or set an explicit `limit`.

`count` without a block or argument delegates to the storage. `Storage::Box` raises `NotSupportedError`
because IPROTO has no count request and calling `index:count()` in Lua requires execute grants on universe
that an application user typically lacks. Pass a block or argument to enumerate instead:

```ruby
User.all.count                               # NotSupportedError on Storage::Box
User.all.count { |user| user.age > 18 }      # enumerates, returns Integer
User.all.count(some_user)                    # enumerates, counts elements equal to some_user
```

## Transactions

`Storage::Box` supports interactive transactions via the Tarantool MVCC engine.

```ruby
User.transaction(isolation: :read_committed, timeout: 5) do
  user = User.create!(id: 1, email: 'a@b.c')
  user.update!(age: 21)
end
```

All models in one transaction must share the same storage instance. A write through a different storage
instance raises `TransactionMismatchError` before sending anything to Tarantool; reads through another
storage are allowed. If the block raises, the transaction rolls back and the error propagates. In-memory
record state (attribute values, `persisted?`) is not reverted on rollback. A nested `transaction` call
raises `Tarantool::TransactionError`. `Storage::Crud` does not support transactions and raises
`NotSupportedError`.

## Storage::Crud

`Storage::Crud` maps the storage contract onto a `Tarantool::Crud::Client`. Require the `tarantool-crud`
gem yourself before using it.

```ruby
require 'tarantool/crud'

crud = Tarantool::Crud::Client.new(Tarantool::Client.new('tcp://app:secret@router:3301'))

class Customer
  include Tarantool::Model

  self.space_name = :users
  attribute :id,    :integer
  attribute :email, :string
  attribute :age,   :integer, default: 0
end

Customer.storage = Tarantool::Model::Storage::Crud.new(crud, primary_index: :primary)
```

Do not declare `bucket_id` as a model attribute; the sharding key is managed by crud and does not need to
appear in your model. Primary key values must be supplied by the caller; crud cannot route a nil sharding key.

Supported iterators: `eq`, `ge`, `gt`, `le`, `lt`, `all`. Any other iterator raises `ArgumentError`. `count`
on a relation works. Schema is not verified on the first operation.

**A wrong `primary_index:` name is treated by crud as a field name and silently returns nothing.** This affects
queries that walk the primary index: `all`, `where`/`find_by` without an index name, and `find_each`. `find` reads
by key with crud `get` and does not use it. Make sure the index name matches the space definition.

Keyset pagination with `after` requires a tuple, which `select` returns but single-row operations (`find`,
`find_by`) do not. Calling `after` on a record loaded with `find` raises `ArgumentError`.

## Testing

`Tarantool::Model::Testing::MemoryStorage` keeps rows in memory, so model specs run without a Tarantool server.
It is loaded only on request:

```ruby
# spec/spec_helper.rb
require 'tarantool/model/testing'

USERS_SPACE = {
  format: [{ name: :id, type: :unsigned }, { name: :email, type: :string },
           { name: :age, type: :unsigned, is_nullable: true }],
  indexes: [{ name: :primary, parts: [:id], sequence: true },
            { name: :email, parts: [:email] },
            { name: :age, parts: [:age], unique: false }]
}.freeze

RSpec.configure do |config|
  config.before do
    User.storage = Tarantool::Model::Testing::MemoryStorage.new({ users: USERS_SPACE })
  end
end
```

Build a new storage for every example; separate instances share nothing.

Spaces are declared like the `ensure_space` arguments of tarantool-schema: `format` entries are
`{ name:, type:, is_nullable: }`; `indexes` is an Array of `{ name:, parts:, unique:, type:, sequence: }` and the
first one is primary; `unique` defaults to true and `type` to `tree`. Parts are field names or
`{ field:, type:, is_nullable: }`. Unknown keys and types raise `ArgumentError`. Spaces are passed as one Hash,
`MemoryStorage.new({ users: SCHEMA, accounts: OTHER }, behaves_like: :crud)`; `behaves_like:` is the only keyword.
A tarantool-schema definition can be passed as is: `MemoryStorage.from_definition(definition)` duck-types
`definition.to_h`.

`behaves_like: :box` (default) keeps the `Storage::Box` contract; `behaves_like: :crud` keeps the
`Storage::Crud` one. What Tarantool would reject is raised with the class the application gets in production:

| Situation | `:box` | `:crud` |
|---|---|---|
| duplicate unique key | `RecordNotUnique` | `RecordNotUnique` |
| nil in a non-nullable field | `Tarantool::ServerError`, code 23 | `Tarantool::Crud::InsertError` / `UpdateError` |
| update of a primary key field | `Tarantool::ServerError`, code 94 | `Tarantool::Crud::UpdateError` |
| `+`/`-` on a non-number | `Tarantool::ServerError`, code 26 | `Tarantool::Crud::UpdateError` |
| key with more parts than the index | `Tarantool::ServerError`, code 31 | — |
| unsupported iterator or `after` on a hash index | `Tarantool::ServerError`, code 112 | — |
| unknown space | `Tarantool::SchemaError` | `Tarantool::Crud::<Operation>Error` |
| `count` | `NotSupportedError` | counts |
| `transaction` | rolls back when the block raises | `NotSupportedError` |
| single-row results | with a tuple | `tuple` is nil |

`verify` (the schema check `Storage::Box` runs on first use) does nothing in `:crud` mode. A nil primary key gets
the next sequence value when the primary index has `sequence: true` (`:box` only). Values are copied through the
client's msgpack codec on write and read, so they come back as from Tarantool: Symbols become Strings (incl. Hash
keys in any/map fields), and changing a returned value never changes the store.

Not modelled:

- value types: only nullability is checked, so a String in an `unsigned` field is stored;
- update operators other than `=`, `+` and `-` (`NotSupportedError`);
- MVCC and concurrency: writes are visible at once, and a transaction is a snapshot restored on error;
- Strings compare bytewise like Tarantool's default collation; values of different classes in one index raise
  `ArgumentError`;
- a `hash` index walks in key order, Tarantool's order is unspecified;
- a partial key on a multi-part `hash` index is matched as a prefix, Tarantool rejects it;
- JSON path parts, `rtree` and `bitset` indexes (`ArgumentError`);
- thread safety.

## Rails

`to_param` joins a composite key with `-` (e.g. `"7-1"`) for route helpers. `as_json` works through
`ActiveModel::Serializers::JSON`. `form_with` works with any persisted model.

There is no Railtie. Configure storage in an initializer:

```ruby
# config/initializers/tarantool.rb
pool = Tarantool::Client::Pool.new(Rails.application.config.tarantool_uris)
User.storage = Tarantool::Model::Storage::Box.new(pool, read: { mode: :prefer_ro }, write: { mode: :rw })
```

## Errors

`Tarantool::Model::Error` descends from `Tarantool::Error`, so one `rescue Tarantool::Error` also catches
client and crud errors.

```
Tarantool::Model::Error
├── RecordNotFound            # #model, #key
├── RecordInvalid             # #record
├── RecordNotSaved            # #record; a before callback aborted
├── RecordNotUnique           # duplicate primary or unique secondary key
├── SchemaMismatchError       # attribute or primary key does not match the space format
├── NotSupportedError         # operation not available for this storage (e.g. count on Storage::Box)
└── TransactionMismatchError  # write through a storage that has no open transaction in the current fiber
```

## Development

```sh
podman compose -f tarantool-model/docker-compose.yml up -d --wait box-2.11 box-3
# or: docker compose -f tarantool-model/docker-compose.yml up -d --wait box-2.11 box-3

cd tarantool-model
bundle exec rspec                                                        # unit specs
INTEGRATION=1 TARANTOOL_MODEL_URI=tcp://app:secret@localhost:3321 bundle exec rspec  # 2.11
INTEGRATION=1 TARANTOOL_MODEL_URI=tcp://app:secret@localhost:3322 bundle exec rspec  # 3.x
```

The `app` user needs `read,write` on universe. Specs truncate spaces through `client.eval`, which requires
`execute` on universe as well; grant `read,write,execute` if truncation is denied.

For `Storage::Crud` specs, start the crud services (requires the `tarantool-crud` docker image):

```sh
podman compose -f tarantool-model/docker-compose.yml up -d --wait --build crud-2.11 crud-3

TARANTOOL_MODEL_CRUD_URI=tcp://app:secret@localhost:3331 bundle exec rspec --tag crud  # 2.11
TARANTOOL_MODEL_CRUD_URI=tcp://app:secret@localhost:3332 bundle exec rspec --tag crud  # 3.x
```

## Public API

`Tarantool::Model`, `Storage::Box`, `Storage::Crud`, `Testing::MemoryStorage`, `Types::UUID`, `Types::Interval`,
`Types::Binary`, `Relation`, and the error classes above.

Everything else, including anything tagged `@api private` in its source comment, is an implementation detail
and may change in any release.

## License

MIT
