# tarantool-ruby

Ruby gems for working with [Tarantool](https://www.tarantool.io) 2.11+ and 3.x. `tarantool-client` is a
low-level IPROTO client; `tarantool-crud` wraps the tarantool/crud module for sharded vshard clusters;
`tarantool-model` adds ActiveModel-based models with validations, callbacks, and keyset pagination on top
of either storage backend.

## Requirements

Ruby >= 3.2, Tarantool 2.11+ or 3.x.

## Install

```sh
gem install tarantool-client
gem install tarantool-crud   # sharded clusters via tarantool/crud
gem install tarantool-model  # ActiveModel models
```

Or in your Gemfile:

```ruby
gem 'tarantool-client'
gem 'tarantool-crud'
gem 'tarantool-model'
```

## Gems

| Gem | |
|---|---|
| [tarantool-client](tarantool-client) | IPROTO client for Tarantool 2.11+ and 3.x |
| [tarantool-crud](tarantool-crud) | Wrapper over tarantool/crud for sharded clusters |
| [tarantool-model](tarantool-model) | ActiveModel-based models over Tarantool spaces |

## Errors

Every error raised by these gems descends from `Tarantool::Error`: the client's own classes such as
`Tarantool::ConnectionError` and `Tarantool::ServerError`, `Tarantool::Crud::Error`, and `Tarantool::Model::Error`.

## License

MIT — see [LICENSE](LICENSE).
