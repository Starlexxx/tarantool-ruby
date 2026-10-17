# Changelog

## 0.3.0 (2026-10-17)

- `select(fetch_position: true)` returns a `Page` with the server-side position of the last tuple; `after:` takes that position (String) as well as a tuple.
- Graceful shutdown: the client subscribes to `box.shutdown`; on the event it stops sending, a `Pool` member leaves the rotation, requests in flight finish, and the connection is closed by the client before the server stops (`shutdown.tarantool` event, `disconnect.tarantool` with the reason `server ... is shutting down`).

## 0.2.0 (2026-10-17)

- `as: :hash` and `as: :row` on `select`, `insert`, `replace`, `update` and `delete` return tuples as Hashes by the space format (`Client::Row` keeps the raw tuple too); `SpaceInfo#to_hash` and `#to_tuple` do the conversion.
- `insert`, `replace` and `upsert` accept a Hash; missing fields go out as nil, an unknown key raises `ArgumentError`.
- The format comes from the schema the request runs against; a schema change makes the server reject the request and the retry rebuilds it by the new format. A numeric space id unknown to the cache costs one reload too, like a name.
- A Hash key unknown to the cached format costs one schema reload; a field still missing after it raises `UnknownFieldError` (an `ArgumentError`). Inside a transaction there is no reload.
- An unknown numeric space id paired with a named index now raises `SchemaError` with "space 'N' not found" instead of "index '...' not found in space N".
- `delete_by`: delete every tuple matching a key on any TREE index, including non-unique ones, in keyset batches; not atomic outside a transaction, the error carries `#deleted`.
- `instrumenter:` option on `Client` and `Pool`: `request.tarantool` for every call and transaction step, plus `disconnect`, `reconnect`, `reconnect_failed`, `fork` and `role_change` events. Payloads carry no keys, tuples, arguments, bindings or credentials; exceptions use ActiveSupport's `exception` and `exception_object` keys.
- `logger:` option: a debug line per request, lifecycle lines, and background warnings that used to go to stderr.

## 0.1.0 (2026-10-16)

First release.

- IPROTO client for Tarantool 2.11+ and 3.x: CRUD by space and index name, call, eval.
- SQL: `execute`, `prepare`.
- Interactive transactions over streams.
- `box.session.push` messages and watchers.
- Background reconnect with exponential backoff and full jitter.
- `Pool` with `:rw`, `:ro`, `:prefer_ro`, `:prefer_rw` and `:any` modes driven by `box.status`.
- `space_info`: space format and index parts from the schema cache.
- `select(after:)` keyset pagination.
- `max_frame_size` configuration option (default 64 MB) caps response frame size; frames exceeding it raise `ProtocolError` and break the connection.
- Per-request unread push messages capped at 10 000; exceeding the cap fails the request with `ProtocolError` without breaking the connection.
- Fork safety: `Client` and `Pool` reinitialize transparently in a child process on first use; streams created before `fork` raise `ConnectionError` in the child.
- `MP_ERROR` values nested deeper than 16 levels raise `ProtocolError` and break the connection instead of overflowing the stack.
- A malformed decimal (more than 38 digits or a scale outside Tarantool's exponent range) raises `ProtocolError` and breaks the connection; the message carries only the payload size.
- `connect_timeout` bounds the whole greeting read, not each byte of it.
- Watcher events are coalesced: events for unwatched keys are dropped and a key keeps only its latest pending value.
- A watcher callback raising any non-fatal exception is reported and no longer stops the dispatcher.
- `close` no longer re-raises an exception that killed an internal thread; a `Pool` reset after `fork` survives inherited threads that died.
- `Configuration#to_h` keeps the password, so `Tarantool::Client.new(**client.config.to_h)` works; `inspect`, `to_s` and `pp` still mask it.
