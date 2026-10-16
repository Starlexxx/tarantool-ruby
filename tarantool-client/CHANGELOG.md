# Changelog

## 0.1.0 (unreleased)

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
