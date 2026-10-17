# tarantool-opentelemetry

OpenTelemetry spans for [tarantool-client](../tarantool-client). The client reports every request and
lifecycle event to an `instrumenter:`; this gem is one that opens a client span per event, so a Tarantool
call shows up in a trace next to the HTTP and SQL spans of the application.

## Installation

Requirements: Ruby >= 3.2, `opentelemetry-api` 1.x; an SDK and exporter configured by the application as
usual (`opentelemetry-sdk`, `opentelemetry-exporter-otlp`).

```ruby
gem 'tarantool-opentelemetry'
```

```ruby
require 'tarantool/opentelemetry'

client = Tarantool::Client.new('tcp://app:secret@db1:3301', instrumenter: Tarantool::OpenTelemetry::Instrumenter.new)
pool = Tarantool::Client::Pool.new(uris, instrumenter: Tarantool::OpenTelemetry::Instrumenter.new)
```

`Pool` hands the instrumenter to every member. tarantool-crud and tarantool-model talk through the client, so
their calls are traced too.

## Options

```ruby
Tarantool::OpenTelemetry::Instrumenter.new(
  instrumenter: ActiveSupport::Notifications,            # chained: receives every event, inside the span
  tracer: OpenTelemetry.tracer_provider.tracer('my-app'), # default: tracer 'tarantool-client', its version
  db_statement: :include                                  # default :omit; :include adds the SQL text
)
```

The chained instrumenter gets the same event name, the same payload object and the original block, so
tarantool-rails' log subscriber or a custom subscriber keeps working under the span.

## Spans

One span per event, kind client, the client's block run inside it (a span current in the caller becomes
the parent).

| Event | Span name | Attributes |
|---|---|---|
| `request.tarantool` | `tarantool.select users`, `tarantool.call crud.get`, `tarantool.execute`, `tarantool.ping`; `tarantool` when a space, index or field name failed to resolve and no request was built | `db.system` `tarantool`, `db.operation`, `db.tarantool.space`, `db.tarantool.index`, `db.tarantool.function`, `db.tarantool.statement_id`, `db.tarantool.schema_reloaded`, `db.statement` (only with `db_statement: :include`), `server.address`, `server.port` |
| `disconnect.tarantool` | `tarantool.disconnect` | `tarantool.reason` |
| `reconnect.tarantool` | `tarantool.reconnect` | `tarantool.attempts` |
| `reconnect_failed.tarantool` | `tarantool.reconnect_failed` | `tarantool.attempts` |
| `fork.tarantool` | `tarantool.fork` | |
| `role_change.tarantool` | `tarantool.role_change` | `tarantool.read_only` |
| `shutdown.tarantool` | `tarantool.shutdown` | `tarantool.pending` |

Every span has `db.system` and, when the payload carries the instance address, `server.address` and
`server.port` (a unix socket path goes to `server.address` alone). An attribute is set only when the payload
has the key; Symbols become Strings, ids stay Integers.

A request that raises gets the exception recorded on the span once, the status set to error with the
exception's message, and the exception re-raised. Keys, tuples, call arguments, SQL bindings and credentials
never appear: the client does not put them in the payload. `db.statement` is opt-in because the SQL text can
carry literals.

## Development

```sh
cd tarantool-opentelemetry
bundle exec rspec                                                                  # unit, no server
INTEGRATION=1 TARANTOOL_URI=tcp://app:secret@localhost:3301 bundle exec rspec     # against a client container
```

The integration specs need one of the tarantool-client containers (`podman compose -f
tarantool-client/docker-compose.yml up -d --wait tarantool-2.11 tarantool-3`, ports 3301 and 3302).

## Public API

`Tarantool::OpenTelemetry::Instrumenter`.

Everything else, including anything tagged `@api private` in its source comment, is an implementation detail
and may change in any release.

## License

MIT, see [LICENSE](LICENSE).
