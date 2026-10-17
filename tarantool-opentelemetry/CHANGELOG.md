# Changelog

## 0.1.0 (unreleased)

First release.

- `Tarantool::OpenTelemetry::Instrumenter`: an `instrumenter:` for `Tarantool::Client` and `Pool` that opens one
  client span per request and lifecycle event, with `db.*` and `server.*` attributes; chains another
  instrumenter; `db_statement: :include` adds the SQL text.
