# tarantool-client

Ruby client for [Tarantool](https://www.tarantool.io) 2.11+ and 3.x over the binary IPROTO protocol.

- One connection serves any number of threads or fibers at once; responses are matched by sync.
- Works under a Fiber Scheduler (e.g. `async`) without depending on it.
- Reconnects in the background with exponential backoff.
- A pool routes requests by instance role (`box.status`).
- Single runtime dependency: `msgpack`.

## Installation

Requirements: Ruby >= 3.2, Tarantool 2.11+ or 3.x.

```ruby
gem 'tarantool-client'
```

```ruby
require 'tarantool/client'
```

## Connecting

```ruby
client = Tarantool::Client.new('tcp://app:secret@localhost:3301', connect_timeout: 1, request_timeout: 5)
client.ping           # => true
client.server_version # => "3.2.0"
client.config         # => the resolved Configuration
client.close
```

URIs: `tcp://user:password@host:port`, `host:port`, `unix:/path/to/socket`. Keyword options win over the URI.

| Option | Default | Meaning |
|---|---|---|
| `user`, `password` | `nil` | chap-sha1 authentication; no user means guest |
| `connect_timeout` | `3` | seconds for connect and handshake, and for a request to wait for a reconnect |
| `request_timeout` | `10` | default timeout of every request; each call accepts `timeout:` |
| `reconnect` | `true` | reconnect in the background after the connection is lost |
| `reconnect_attempts` | `Float::INFINITY` | failed attempts before the client gives up |
| `reconnect_delay` | `0.1` | base delay of the exponential backoff |
| `reconnect_max_delay` | `5` | cap of the backoff delay |
| `max_frame_size` | `67108864` (64 MB) | maximum allowed response frame size in bytes; larger frames raise `ProtocolError` and break the connection |

Tarantool Community Edition has no TLS support. Authentication uses chap-sha1; the password is never sent in clear. `client.inspect` leaves the password out, and `Configuration#inspect`, `#to_s` and `pp` replace it with `[FILTERED]`. `Configuration#to_h` keeps it, so `Tarantool::Client.new(**client.config.to_h)` connects with the same credentials; don't log it.

## Data

Spaces and indexes accept names (Symbol or String) or numeric ids.

```ruby
client.select(:users, [42])
client.select(:users, ['a@b.c'], index: :email, limit: 10, offset: 0, iterator: :ge)
client.insert(:users, [42, 'a@b.c', 0])
client.replace(:users, [42, 'x@y.z', 0])
client.update(:users, [42], [['=', 1, 'new@b.c']])
client.upsert(:users, [42, 'a@b.c', 0], [['+', 2, 1]])
client.delete(:users, [42])
```

IPROTO update operations use 0-based field numbers: field 0 is the first field, field 1 the second, and so on.

Names are resolved through a schema cache loaded from `_vspace` and `_vindex`. A request resolved by name carries the schema version. If the schema changed meanwhile, the server rejects the request without running it; the client then reloads the schema once and retries within the same timeout.

`after:` continues a `select` past a tuple (keyset pagination, `IPROTO_AFTER_TUPLE`). It works on TREE indexes, including non-unique ones and `:lt`/`:le` (descending); a HASH index raises `ServerError` (code 112).

```ruby
page = client.select(:users, [18], index: :age, iterator: :ge, limit: 50)
next_page = client.select(:users, [18], index: :age, iterator: :ge, limit: 50, after: page.last)
```

`space_info` returns the format and indexes from the same schema cache; an unknown name costs one reload. Inside a transaction it reads the schema the transaction started with; on a `Pool` it accepts `mode:`.

```ruby
info = client.space_info(:users)
info.fields.map(&:name)              # => ["id", "email", "age"]
info.primary_index.parts.map(&:name) # => ["id"]
info.indexes['age'].unique           # => false
```

`as: :hash` returns tuples as Hashes keyed by field name; fields beyond the format are keyed by their 0-based position. `as: :row` returns `Client::Row` with the raw `tuple` and its `attributes`. `insert`, `replace` and `upsert` take a Hash too: Symbol or String names, missing fields go out as nil, an unknown name raises `ArgumentError`. A key may also be an Integer position past the format, up to 1024 positions beyond it; a negative position or one further out also raises `ArgumentError`. The format comes from the same schema the request carries the version of, so an alter in between makes the server reject the request and the client rebuilds it by the new format. This works the same in transactions and on a `Pool`.

```ruby
client.insert(:users, { id: 42, email: 'a@b.c', age: 0 })
client.select(:users, [42], as: :hash) # => [{ id: 42, email: "a@b.c", age: 0 }]
row = client.select(:users, [42], as: :row).first
row.tuple                              # => [42, "a@b.c", 0]
row.attributes                         # => { id: 42, email: "a@b.c", age: 0 }
info.to_hash([42, 'a@b.c', 0])         # => { id: 42, email: "a@b.c", age: 0 }
```

## Lua

```ruby
client.call('api.get_user', [42])
client.eval('return ...', [1, 2])
client.call('long_job', [], on_push: ->(message) { puts message }) # box.session.push messages
```

`api.get_user` and `long_job` stand for Lua functions you define on the server; `call` needs `execute` on them.

## SQL

```ruby
result = client.execute('SELECT * FROM "users" WHERE "id" = ?', [42])
result.rows      # => [[42, "a@b.c", 0]]
result.columns   # => ["id", "email", "visits"]
result.row_count # DML only

statement = client.prepare('SELECT * FROM "users" WHERE "id" = ?')
statement.execute([42])
statement.close
```

Tarantool 2.x uppercases unquoted identifiers, so `FROM users` fails with "Space 'USERS' does not exist" on 2.11; quote both table and column names to work on both versions. `SqlResult` is not `Enumerable`; iterate rows with `result.rows.each`.

## Transactions

Interactive transactions run on their own IPROTO stream and need `memtx_use_mvcc_engine = true` on the server.

```ruby
client.transaction(isolation: :read_committed, timeout: 5) do |tx|
  tx.insert(:users, [43, 'b@c.d', 0])
  tx.update(:users, [42], [['+', 2, 1]])
end
```

The block argument is a `Tarantool::Client::Stream` and supports the same data operations as `Client`. The block's value is returned after COMMIT. Any other exit from the block rolls the transaction back. Isolation levels: `:default`, `:read_committed`, `:read_confirmed`, `:best_effort`, `:linearizable`. A nested `transaction` raises `TransactionError`, and so does a schema change during the transaction (retry the whole transaction).

## Watchers

```ruby
watcher = client.watch('box.status') { |key, value| puts value['is_ro'] }
watcher.unwatch
```

The block gets the current value first (`nil` if the key was never broadcast), then every change. Blocks run on one dispatcher thread per client; exceptions are reported with `warn`.

## Reconnect

- When the connection is lost, every request waiting for a reply fails with `ConnectionError`. Requests are never retried automatically.
- A background thread reconnects with exponential backoff and full jitter. Rejected credentials count as a failed attempt.
- Requests issued meanwhile wait for the new connection up to `connect_timeout` (and never past their own timeout), then raise `ConnectionError`.
- After reconnecting, the client performs the handshake and loads the schema of the new instance before any request can use it. It then subscribes the watchers again, and each watcher gets the current value.
- A transaction cannot survive a reconnect: the server rolls it back, and the next call in the block raises `TransactionError`.
- Prepared statements belong to the old session and are gone.
- After `reconnect_attempts` failures the client stops, and every request raises `ConnectionError`. With `reconnect: false`, requests after a loss raise `ConnectionError` right away.

## Pool

```ruby
pool = Tarantool::Client::Pool.new(%w[tcp://db1:3301 tcp://db2:3301], user: 'app', password: 'secret')
pool.select(:users, [42], mode: :prefer_ro)
pool.insert(:users, [44, 'c@d.e', 0], mode: :rw)
pool.transaction { |tx| tx.delete(:users, [44]) } # always on a writable instance
pool.close
```

`watch`, `server_version`, and `connected?` are available on `Client` only, not on `Pool`. Every other operation accepts `mode:`:

| Mode | Instances |
|---|---|
| `:any` (default) | every instance whose role is known |
| `:rw` | writable ones |
| `:ro` | read-only ones |
| `:prefer_ro` | read-only ones, writable if none |
| `:prefer_rw` | writable ones, read-only if none |

Roles come from `box.status` (`is_ro`), so a switchover is picked up as soon as the instances report it. Requests are spread round-robin among matching instances. If none matches, the call raises `NoAvailableInstanceError`. `Pool.new` raises it only if no address answers; addresses that are down keep being retried in the background. That retrying covers start-up only: once connected, a member relies on its client's reconnect, so with a finite `reconnect_attempts` a member that gives up stays out of rotation. `Pool#close` may wait for an in-progress background connect attempt, up to `connect_timeout` + `request_timeout`. Options are passed to each client. A prepared statement from `pool.prepare` stays bound to the instance that prepared it.

## Forking servers

`Client` and `Pool` are fork-safe. The first request in a child process after `fork` reinitializes the connection transparently — a new socket is opened, background threads are restarted, and watchers are resubscribed. The parent's connection is unaffected.

Streams (interactive transactions) cannot cross a fork boundary. Using a stream that was created before `fork` in a child raises `ConnectionError`.

No configuration is needed; the detection is a single PID comparison on every request.

## Errors

```
Tarantool::Error
├── ConnectionError            # refused, lost or broken connection; low-level errors are in #cause
│   └── ClientClosedError
├── TimeoutError
├── AuthenticationError        # #code
├── ProtocolError
├── SchemaError                # unknown space or index name
├── ServerError                # #code, #error_stack, #schema_version
├── TransactionError
└── NoAvailableInstanceError
```

The error classes are flat under `Tarantool::`, e.g. `Tarantool::ServerError`, not `Tarantool::Client::ServerError`.
tarantool-crud and tarantool-model errors also descend from `Tarantool::Error`.

`Tarantool::UnknownFieldError` (an `ArgumentError`, not under `Tarantool::Error`) is raised for a Hash tuple key naming a field missing from the format.

`box.error` objects inside returned data decode into `Tarantool::Client::BoxError`.

## Development

```sh
bundle install                          # from the repo root; the gem has no Gemfile of its own
cd tarantool-client
bundle exec rspec                       # unit specs
docker compose -f docker-compose.yml up -d --wait
INTEGRATION=1 TARANTOOL_URI=tcp://app:secret@localhost:3301 bundle exec rspec   # 2.11; 3302 for 3.x
bundle exec rubocop
```

Reconnect and pool specs restart their own pair of instances:

```sh
docker compose -p tarantool-failover -f docker-compose.yml --profile failover up -d --wait failover-a failover-b
TARANTOOL_FAILOVER_URIS=tcp://app:secret@localhost:3311,tcp://app:secret@localhost:3312 \
TARANTOOL_FAILOVER_CONTAINERS=tarantool-failover-failover-a-1,tarantool-failover-failover-b-1 \
bundle exec rspec --tag failover
```

Using podman instead of docker: prefix the `bundle exec rspec --tag failover` command above with `CONTAINER_CLI=podman`; the reconnect spec uses it to restart containers (default `docker`).

## Public API

`Tarantool::Client`, `Tarantool::Client::Pool`, `Tarantool::Client::Stream` (yielded by `transaction`),
`Watcher` (returned by `watch`), `SqlResult`, `PreparedStatement`, `SpaceInfo`, `IndexInfo`, `Row`, `Configuration`
(returned by `client.config`), `Tarantool::Client::UUID`, `Interval`, `BoxError`, and the error classes above.

Everything else, including anything tagged `@api private` in its source comment, is an implementation detail
and may change in any release.

## License

MIT
