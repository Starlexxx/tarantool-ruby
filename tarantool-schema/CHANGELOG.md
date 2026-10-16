# Changelog

## Unreleased

First release.

- `Tarantool::Schema::Definition`: `ensure_space` and `ensure_index` with `plan` and `apply` over an admin
  `Tarantool::Client`. Creates missing spaces, indexes and primary key sequences; raises `MismatchError` with a
  diff when the live schema differs, before creating anything. Never alters or drops.
- `Definition#to_h`: the normalized declaration, with defaults filled in and part types inherited; tarantool-model's
  `Testing::MemoryStorage.from_definition` accepts the definition.
- Depends on `tarantool-client ~> 0.1.0`.
