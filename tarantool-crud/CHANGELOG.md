# Changelog

## 0.1.1 (2026-10-17)

- Depends on `tarantool-client ~> 0.2.0`.

## 0.1.0 (2026-10-16)

First release.

- `Tarantool::Crud::Client` over `Tarantool::Client` or `Pool`, per-space handles.
- insert, replace, upsert (tuple or object), get, update, delete, select, each, count, min, max, len, truncate.
- `*_many` and `*_many!` batch operations.
- Conditions from Arrays or Hashes with ranges.
- Read and write defaults filtered by the options each crud function accepts.
- `storage_info` and `stats`; `stats` accepts `timeout:` and falls back to the `read:` timeout plus `timeout_margin`.
- Depends on `tarantool-client ~> 0.1.0`.
