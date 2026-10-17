# Changelog

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
