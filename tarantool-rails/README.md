# tarantool-rails

Rails integration for [tarantool-client](../tarantool-client), [tarantool-model](../tarantool-model) and
[tarantool-schema](../tarantool-schema). One gem gives an application `config/tarantool.yml` per environment,
one connection pool per process, models on that pool without an initializer, ActiveRecord-style request lines
in the Rails log with a `Tarantool: 1.2ms` share in "Completed" lines, `tarantool:schema:*` rake tasks and
generators for the configuration and for models.

## Installation

Requirements: Ruby >= 3.2, Rails 7.1+, Tarantool 2.11+ or 3.x.

```ruby
gem 'tarantool-rails'
gem 'tarantool-crud'   # only for storage: crud
```

```sh
rails g tarantool:install   # config/tarantool.yml and config/tarantool_schema.rb
```

## config/tarantool.yml

Read with `config_for`, so ERB, a `shared` section and the environment sections work as in `database.yml`.

```yaml
default: &default
  user: app
  password: <%= ENV["TARANTOOL_PASSWORD"] %>
  connect_timeout: 3
  request_timeout: 10

development:
  <<: *default
  addresses: [tcp://localhost:3301]
  admin_uri: tcp://app:secret@localhost:3301

test:
  <<: *default
  addresses: [tcp://localhost:3301]

production:
  <<: *default
  addresses:
    - tcp://db1:3301
    - tcp://db2:3301
  read:  { mode: prefer_ro }
  write: { mode: rw }
  admin_uri: <%= ENV["TARANTOOL_ADMIN_URI"] %>
```

| Key | |
|---|---|
| `addresses` | required, Array of URIs; `address` with a single String is accepted too |
| `user`, `password`, `connect_timeout`, `request_timeout`, `reconnect`, `reconnect_attempts`, `reconnect_delay`, `reconnect_max_delay`, `max_frame_size` | passed to `Tarantool::Client::Pool.new` as they are |
| `read`, `write` | options for `Storage::Box`: `mode` (`prefer_ro`, `rw`, ...) and `timeout` |
| `storage` | `box` (default) or `crud` |
| `crud` | for `storage: crud`: `primary_index` (default `primary`), `read`, `write` and `timeout_margin` for `Tarantool::Crud::Client.new` |
| `admin_uri` | connection for the schema rake tasks, a user that may create spaces |

Any other key raises `ArgumentError` at boot. A missing file is not an error at boot, so the install generator
can run; the first model operation then raises `Tarantool::Rails::Error`.

## What the Railtie does

- `Tarantool::Rails.config` holds the environment section as a `Configuration` (its `inspect` hides the
  password).
- `Tarantool::Rails.pool` is one `Tarantool::Client::Pool` per process, built on first use with
  `instrumenter: ActiveSupport::Notifications`. After `fork` the pool reopens its connections on its own.
  `config.tarantool.instrumenter` replaces the instrumenter; the log subscriber still needs the events on
  `ActiveSupport::Notifications`, so chain it:

  ```ruby
  # config/initializers/tarantool.rb
  Rails.application.config.tarantool.instrumenter =
    Tarantool::OpenTelemetry::Instrumenter.new(instrumenter: ActiveSupport::Notifications)
  ```
- `Tarantool::Rails.storage` is a `Storage::Box` (or `Storage::Crud`) over the pool, and
  `Tarantool::Model.default_storage` is set so every model without a storage of its own uses it. Nothing
  connects until a model is used.
- `Tarantool::Rails::LogSubscriber` writes a line per request and `ControllerRuntime` adds the Tarantool time
  to "Completed" lines; turn both off with `config.tarantool.log = false`.
- `Tarantool::Rails.schema` is the `Tarantool::Schema::Definition` from `config/tarantool_schema.rb`
  (`config.tarantool.schema_path` changes the file).
- `Tarantool::Rails.disconnect!` closes the pool; the next use builds a new one.

```ruby
class User
  include Tarantool::Model

  attribute :id,    :integer
  attribute :email, :string
end

User.create!(email: 'a@b.c')   # through Tarantool::Rails.storage
```

## Log

```
Tarantool insert users (0.31ms) db1:3301
Tarantool select users by email (0.18ms) db2:3301
Tarantool call user.touch (0.42ms) db1:3301
Tarantool execute (0.57ms) SELECT COUNT(*) FROM "users" db1:3301
Tarantool update users (0.26ms) db1:3301 Tarantool::ServerError(3)
Completed 200 OK in 4ms (Views: 1.9ms | Tarantool: 0.5ms)
```

Request lines are debug, colored like ActiveRecord's when `colorize_logging` is on. Keys, tuples and
arguments never appear: the client does not put them in the event payload. A failed request shows the error
class and code, not the message. Lifecycle events are logged too: `disconnect` at warn, `reconnect_failed` at
error, `reconnect`, `fork`, `role_change` and `shutdown` at info.

## Schema

`config/tarantool_schema.rb` assigns the definition:

```ruby
Tarantool::Rails.schema = Tarantool::Schema::Definition.new do
  ensure_space :users,
               format: [{ name: :id, type: :unsigned }, { name: :email, type: :string }],
               indexes: [{ name: :primary, parts: [:id], sequence: true }, { name: :email, parts: [:email] }]
end
```

| Task | |
|---|---|
| `rails tarantool:schema:plan` | prints what `apply` would create; drift raises `MismatchError` with the diff |
| `rails tarantool:schema:apply` | creates the missing spaces, indexes and grants and prints them; never drops |
| `rails tarantool:schema:check` | for CI: exits 1 and prints `pending: ...` when anything would be created, 0 when live equals declared |
| `rails tarantool:schema:dump` | writes the live schema to `config/tarantool_schema.rb` for bootstrapping; refuses to overwrite unless `FORCE=1`; `dump[users,codes]` limits the spaces |

`plan`, `apply` and `check` take the tarantool-schema `alter:` names as an argument: `rails
"tarantool:schema:apply[add_field]"` appends nullable fields declared past the end of a live format. Without it
such a format is drift. The tasks connect with `admin_uri`; see the tarantool-schema README for the privileges
that user needs.

## Generators

```sh
rails g tarantool:model User email:string age:unsigned? token:uuid
```

writes `app/models/user.rb`

```ruby
class User
  include Tarantool::Model

  attribute :id, :integer
  attribute :email, :string
  attribute :age, :integer
  attribute :token, Tarantool::Model::Types::UUID.new
end
```

and adds the space to `config/tarantool_schema.rb` (skip with `--skip-schema`):

```ruby
  ensure_space :users,
               format: [
                 { name: :id, type: :unsigned },
                 { name: :email, type: :string },
                 { name: :age, type: :unsigned, is_nullable: true },
                 { name: :token, type: :uuid }
               ],
               indexes: [
                 { name: :primary, parts: [:id], sequence: true }
               ]
```

`id` is added first as `unsigned` with a sequence unless you list it yourself. A `?` suffix makes the field
nullable. Types: `integer`, `unsigned`, `string`, `boolean`, `decimal`, `datetime`, `uuid`, `interval`,
`binary`. `Admin::User` gets the space `admin_users`, the plural tarantool-model uses.

## Testing

Point the default storage at tarantool-model's in-memory storage, built from the same declaration the deploy
applies. No connection is made in the test environment unless something reads `Tarantool::Rails.pool`.

```ruby
# spec/rails_helper.rb
require 'tarantool/model/testing'

RSpec.configure do |config|
  config.before do
    Tarantool::Model.default_storage = Tarantool::Model::Testing::MemoryStorage.from_definition(Tarantool::Rails.schema)
  end
end
```

## storage: crud

```yaml
production:
  addresses: [tcp://router1:3301, tcp://router2:3301]
  storage: crud
  crud:
    primary_index: primary
    read:  { mode: read, prefer_replica: true }
```

Models then go through `Tarantool::Model::Storage::Crud` over `Tarantool::Crud::Client`; the `tarantool-crud`
gem must be in the Gemfile.

## Public API

`Tarantool::Rails` (`config`, `pool`, `storage`, `schema`, `admin_client`, `disconnect!`),
`Tarantool::Rails::Configuration`, `Tarantool::Rails::LogSubscriber`, `Tarantool::Rails::Error`
(descends from `Tarantool::Error`), the rake tasks and the generators.

RBS signatures for this API ship with the gem in `sig/`.

Everything else, including anything tagged `@api private` in its source comment, is an implementation detail
and may change in any release.

## Development

```sh
podman compose -f tarantool-client/docker-compose.yml up -d --wait tarantool-2.11 tarantool-3
# or: docker compose -f tarantool-client/docker-compose.yml up -d --wait tarantool-2.11 tarantool-3

cd tarantool-rails
bundle exec rspec                                                                 # unit
INTEGRATION=1 TARANTOOL_URI=tcp://app:secret@localhost:3301 bundle exec rspec    # 2.11
INTEGRATION=1 TARANTOOL_URI=tcp://app:secret@localhost:3302 bundle exec rspec    # 3.x
```

## License

MIT, see [LICENSE](LICENSE).
