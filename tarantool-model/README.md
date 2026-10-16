# tarantool-model

ActiveModel-based models for Tarantool 2.11+ and 3.x spaces. Provides attributes, validations, callbacks,
dirty tracking, JSON serialization, and index-based queries with keyset pagination. This is not ActiveRecord:
there is no schema migration, no associations, and no query builder. Storage is `Storage::Box` over
`tarantool-client`; `Storage::Crud` over tarantool/crud comes in the next release.

## Installation

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
     .first                                          # limit(1).to_a.first
     .to_a                                           # Array of model instances

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

```
Tarantool::Model::Error
├── RecordNotFound         # #model, #key
├── RecordInvalid          # #record
├── RecordNotSaved         # #record; a before callback aborted
├── RecordNotUnique        # duplicate primary or unique secondary key
├── SchemaMismatchError    # attribute or primary key does not match the space format
├── NotSupportedError      # operation not available for this storage (e.g. count on Storage::Box)
└── TransactionMismatchError  # arrives with transaction support in the next release
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

## License

MIT
