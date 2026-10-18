# Changelog

## 0.3.0 (unreleased)

- `config.tarantool.instrumenter` replaces `ActiveSupport::Notifications` as the pool instrumenter, for chaining
  tarantool-opentelemetry.
- Depends on `tarantool-client ~> 0.3`, like the other gems.
- The schema rake tasks no longer define helper methods and a constant on `Object`.

## 0.2.0 (2026-10-17)

- `tarantool:schema:dump` writes the live schema to `config/tarantool_schema.rb` (`FORCE=1` to overwrite,
  `dump[users,codes]` to limit the spaces).
- `plan`, `apply` and `check` take `alter` names as a task argument: `"tarantool:schema:apply[add_field]"`.
- `LogSubscriber` logs `shutdown.tarantool` (tarantool-client 0.3.0) at info.
- Depends on `tarantool-schema ~> 0.2`.

## 0.1.0 (2026-10-17)

First release.

- `config/tarantool.yml` per environment through `config_for`; `Tarantool::Rails.config`, `pool` (one per
  process), `storage`, `schema`, `admin_client`, `disconnect!`.
- Models use the configured storage through `Tarantool::Model.default_storage`, built on first use.
- `Tarantool::Rails::LogSubscriber`: ActiveRecord-style request and lifecycle lines; `ControllerRuntime` adds
  `Tarantool: 1.2ms` to "Completed" lines.
- Rake tasks `tarantool:schema:plan`, `apply` and `check`.
- Generators `tarantool:install` and `tarantool:model`.
- Depends on `railties >= 7.1, < 9`, `tarantool-client ~> 0.2`, `tarantool-model ~> 0.3`, `tarantool-schema ~> 0.1`.
