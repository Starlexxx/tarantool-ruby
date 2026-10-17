# tarantool-ruby

Ruby gems for working with [Tarantool](https://www.tarantool.io) 2.11+ and 3.x. `tarantool-client` is a
low-level IPROTO client; `tarantool-crud` wraps the tarantool/crud module for sharded vshard clusters;
`tarantool-model` adds ActiveModel-based models with validations, callbacks, and keyset pagination on top
of either storage backend. `tarantool-schema` declares spaces and indexes idempotently on deploy.
`tarantool-rails` wires all of them into a Rails application; `tarantool-opentelemetry` turns the client's
events into OpenTelemetry spans.

## Documentation

API docs for every gem: https://starlexxx.github.io/tarantool-ruby/ (generated with YARD from master).

## Requirements

Ruby >= 3.2, Tarantool 2.11+ or 3.x.

## Install

```sh
gem install tarantool-client
gem install tarantool-crud   # sharded clusters via tarantool/crud
gem install tarantool-model  # ActiveModel models
gem install tarantool-schema # idempotent schema declaration
gem install tarantool-rails  # Rails integration
gem install tarantool-opentelemetry  # spans for the client's events
```

Or in your Gemfile:

```ruby
gem 'tarantool-client'
gem 'tarantool-crud'
gem 'tarantool-model'
gem 'tarantool-schema'
gem 'tarantool-rails'
gem 'tarantool-opentelemetry'
```

## Gems

| Gem | |
|---|---|
| [tarantool-client](tarantool-client) | IPROTO client for Tarantool 2.11+ and 3.x |
| [tarantool-crud](tarantool-crud) | Wrapper over tarantool/crud for sharded clusters |
| [tarantool-model](tarantool-model) | ActiveModel-based models over Tarantool spaces |
| [tarantool-schema](tarantool-schema) | Idempotent schema declaration for deploys |
| [tarantool-rails](tarantool-rails) | Railtie: config/tarantool.yml, log lines, schema tasks, generators |
| [tarantool-opentelemetry](tarantool-opentelemetry) | OpenTelemetry spans from the client's instrumenter |

## Errors

Every error raised by these gems descends from `Tarantool::Error`: the client's own classes such as
`Tarantool::ConnectionError` and `Tarantool::ServerError`, `Tarantool::Crud::Error`, `Tarantool::Model::Error`,
`Tarantool::Schema::Error`, and `Tarantool::Rails::Error`.

## Development

```sh
bundle install
bundle exec rubocop
bundle exec rake rbs   # validates the RBS signatures in each gem's sig/ and runs the unit suites under rbs/test
```

Each gem's README has its own test commands and the containers it needs.

## License

MIT — see [LICENSE](LICENSE).
