# tarantool-crud

Ruby wrapper over [tarantool/crud](https://github.com/tarantool/crud) for sharded (vshard) Tarantool 2.11+ and 3.x
clusters, built on [tarantool-client](../tarantool-client).

## Installation

Requirements: Ruby >= 3.2, Tarantool 2.11+ or 3.x, tarantool/crud module installed on routers (tested with 1.8.0).

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
users.upsert({ id: 1, email: 'a@b.c', age: 20 }, [['+', 'age', 1]])  # => nil
users.delete(1)

page = users.select({ age: 18.. }, first: 50)        # Result
users.select({ age: 18.. }, first: 50, after: page.last)  # after: accepts a Hash row or a tuple Array
users.each({ age: 18.. }, batch_size: 500) { |row| } # Enumerator without a block; batch_size is the page size of underlying selects
users.count({ age: 18...65 })
users.min(:age_index)
users.len
users.truncate

result = users.insert_many(rows)                     # ManyResult, never raises crud errors
result.errors                                        # [Tarantool::Crud::CallError, ...] with #operation_data
users.insert_many!(rows)                             # raises Tarantool::Crud::ManyError

pairs = [
  [{ id: 1, email: 'a@b.c', age: 20 }, [['+', 'age', 1]]],
  [{ id: 2, email: 'b@c.d', age: 25 }, [['+', 'age', 1]]],
]
users.upsert_many(pairs)                             # each element is [tuple, operations]

crud.storage_info
crud.stats(:users)
```

Any object responding to `call(function, arguments, timeout:)` can serve as the transport: `Tarantool::Client` or
`Tarantool::Client::Pool`.

Write Hash tuples and Hash conditions with braces. Bare `key: value` arguments are crud options.

Requests go through the `Tarantool::Client` you pass in, so its `instrumenter:` and `logger:` see every crud call
as `request.tarantool` with `request: :call` and `function: 'crud.select'` (or the other crud function), without
arguments.

## Results

`select` returns a `Result`: Enumerable of Hash rows (Symbol keys, taken from crud's metadata), plus `tuples`
(raw Arrays), `metadata`, `first`, `last`, `size`, `empty?`. `each` yields the same Hash rows page by page, and
returns an Enumerator without a block. Single-row operations (`get`, `insert`, `update`, ...) return a Hash row or
`nil`, not a `Result`; `upsert` always returns `nil`.

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

`read:` defaults apply to `get select each count min max len storage_info stats`. `write:` defaults apply to the
other operations. crud rejects options a function does not know, so a default is sent only to functions that accept
it: `prefer_replica`/`balance` skip `min`/`max`, and `truncate` gets only `timeout`/`vshard_router`. Options given
to a call are never filtered. Use Symbol keys.

`stats` takes only `timeout:` and sends crud no options: the given or default timeout, plus `timeout_margin`, only
bounds the request.

The `mode:` option here is the crud/vshard router option (`'read'` or `'write'` strings), not the `Pool` routing mode (which uses symbols like `:prefer_ro`).

## Errors

`Tarantool::Crud::Error` has `message` (the crud error message), `str` (crud's `tostring` of the full error, e.g. `"InsertError: ..."`), `class_name`, `file`, `line`, and `operation_data`. Subclasses: `InsertError`,
`ReplaceError`, `UpsertError`, `GetError`, `UpdateError`, `DeleteError`, `SelectError`, `CountError`, `MinMaxError`,
`LenError`, `TruncateError`, `CallError`, `InsertManyError`, `ReplaceManyError`, `UpsertManyError`.
`Tarantool::Crud::ManyError` is a separate `Tarantool::Error` subclass raised by the `*_many!` bang variants; it
carries `result` (and `errors`), not the crud error fields. Transport and server errors from tarantool-client
propagate unchanged.

A crud `timeout:` that runs out on the router arrives as the function's `Crud::*Error` with "Timeout exceeded"
in the message. Only a request that gets no answer within the transport timeout (`timeout:` plus
`timeout_margin`) raises `Tarantool::TimeoutError`.

## Development

```sh
podman compose -f tarantool-crud/docker-compose.yml up -d --wait
cd tarantool-crud
INTEGRATION=1 TARANTOOL_CRUD_URI=tcp://app:secret@localhost:3311 bundle exec rspec
```

Compose pulls `ghcr.io/starlexxx/tarantool-crud:2.11` and `:3` (Tarantool with vshard and crud from
`docker/Dockerfile`), built by the `Images` workflow whenever `docker/` changes. If the pull is denied, log in
with `podman login ghcr.io` and a token that has `read:packages`. To try a Dockerfile change locally:

```sh
docker build -t ghcr.io/starlexxx/tarantool-crud:3 --build-arg TARANTOOL_VERSION=3 tarantool-crud/docker
```

## Public API

`Tarantool::Crud::Client`, `Space`, `Result`, `ManyResult`, and the error classes above.

Everything else, including anything tagged `@api private` in its source comment, is an implementation detail
and may change in any release.
