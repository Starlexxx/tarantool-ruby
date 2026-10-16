# Changelog

## Unreleased

First release.

- `Tarantool::Schema::Definition`: `ensure_space` and `ensure_index` with `plan` and `apply` over an admin
  `Tarantool::Client`. Creates missing spaces, indexes and primary key sequences; raises `MismatchError` with a
  diff when the live schema differs, before creating anything. Never alters or drops.
- `Definition#to_h`: normalized declaration shared with tarantool-model's `MemoryStorage.from_definition`.
- Depends on `tarantool-client ~> 0.1.0`.
