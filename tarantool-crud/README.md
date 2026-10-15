# tarantool-crud

Ruby wrapper over [tarantool/crud](https://github.com/tarantool/crud) for sharded (vshard) Tarantool 2.11+ and 3.x
clusters, built on [tarantool-client](../tarantool-client).

## Installation

```ruby
gem 'tarantool-crud'
```

```ruby
require 'tarantool/crud'
```

crud must be installed and initialised on the routers the client connects to.

## Usage

```ruby
pool = Tarantool::Client::Pool.new(['tcp://app:secret@router-1:3301', 'tcp://app:secret@router-2:3301'])
crud = Tarantool::Crud::Client.new(pool, read: { mode: 'read', balance: true }, write: {}, timeout_margin: 0.5)
users = crud.space(:users)

users.insert([1, nil, 'a@b.c', 20])                  # crud.insert
users.insert({ id: 1, email: 'a@b.c', age: 20 })     # crud.insert_object
users.get(1)                                         # => { id: 1, bucket_id: 7, email: "a@b.c", age: 20 } or nil
users.update(1, [['+', 'age', 1]])
users.upsert({ id: 1, email: 'a@b.c', age: 20 }, [['+', 'age', 1]])
users.delete(1)

page = users.select({ age: 18.. }, first: 50)        # Result
users.select({ age: 18.. }, first: 50, after: page.last)
users.each({ age: 18.. }, batch_size: 500) { |row| } # Enumerator without a block
users.count({ age: 18...65 })
users.min(:age_index)
users.len
users.truncate

result = users.insert_many(rows)                     # ManyResult, never raises crud errors
result.errors                                        # [Tarantool::Crud::CallError, ...] with #operation_data
users.insert_many!(rows)                             # raises Tarantool::Crud::ManyError

crud.storage_info
crud.stats(:users)
```

Any object responding to `call(function, arguments, timeout:)` can serve as the transport: `Tarantool::Client` or
`Tarantool::Client::Pool`.

Write Hash tuples and Hash conditions with braces. Bare `key: value` arguments are crud options.

## Results

`select` and `each` return a `Result`: Enumerable of Hash rows (Symbol keys, taken from crud's metadata), plus
`tuples` (raw Arrays), `metadata`, `first`, `last`, `size`, `empty?`. Single-row operations (`get`, `insert`,
`update`, ...) return a Hash row or `nil`, not a `Result`.

`insert_many`/`replace_many`/`upsert_many` return a `ManyResult`, which adds `errors` and `success?`. If the whole
call fails (missing space, empty row list, ...), crud reports it as `InsertManyError`/`ReplaceManyError`/
`UpsertManyError` inside `errors` with no rows, rather than raising.

## Conditions

An Array of `[operator, field, value]` or a Hash:

| Hash value | Conditions |
|---|---|
| `18` | `['==', 'age', 18]` |
| `18..65` | `['>=', 'age', 18], ['<=', 'age', 65]` |
| `18...65` | `['>=', 'age', 18], ['<', 'age', 65]` |
| `18..` / `..65` / `...65` | `['>=', 'age', 18]` / `['<=', 'age', 65]` / `['<', 'age', 65]` |

## Options

Keyword options go to crud unchanged. `timeout:` is also used as the request timeout plus `timeout_margin`.

`read:` defaults apply to `get select each count min max len storage_info`. `write:` defaults apply to the
other operations. crud rejects options a function does not know, so a default is sent only to functions that accept
it: `prefer_replica`/`balance` skip `min`/`max`, and `truncate` gets only `timeout`/`vshard_router`. Options given
to a call are never filtered. Use Symbol keys.

## Errors

`Tarantool::Crud::Error` (`class_name`, `str`, `file`, `line`, `operation_data`) and its subclasses `InsertError`,
`ReplaceError`, `UpsertError`, `GetError`, `UpdateError`, `DeleteError`, `SelectError`, `CountError`, `MinMaxError`,
`LenError`, `TruncateError`, `CallError`, `InsertManyError`, `ReplaceManyError`, `UpsertManyError`, `ManyError`.
Transport and server errors from tarantool-client propagate unchanged.

## Development

```sh
podman compose -f tarantool-crud/docker-compose.yml up -d --wait --build
cd tarantool-crud
INTEGRATION=1 TARANTOOL_CRUD_URI=tcp://app:secret@localhost:3311 bundle exec rspec
```
