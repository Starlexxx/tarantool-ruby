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
