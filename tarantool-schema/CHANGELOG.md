# Changelog

## 0.3.0 (2026-10-18)

- `grant user, privileges, on: space` declares the privileges a user or role must have on a space. `plan` and
  `apply` grant what is missing after the space and its indexes, keep extra privileges, never revoke, and raise
  `MismatchError` for a grantee that does not exist. `from_live` reads grants, `to_ruby` renders them,
  `Definition#grants` lists them. The deploy user needs `read,write` on `_priv` and `read` on `_user` for this.

## 0.2.1 (2026-10-17)

- Depends on `tarantool-client ~> 0.3`.

## 0.2.0 (2026-10-17)

- `Definition.from_live(client, only:)`: the live user spaces as a definition, for bootstrapping an existing
  database; `Definition#to_ruby` renders a definition as DSL source.
- `plan`/`apply` take `alter: [:add_field]` to append nullable fields to the end of a live format. Without it a
  longer declared format stays a mismatch, as before.

## 0.1.0 (2026-10-17)

First release.

- `Tarantool::Schema::Definition`: `ensure_space` and `ensure_index` with `plan` and `apply` over an admin
  `Tarantool::Client`. Creates missing spaces, indexes and primary key sequences; raises `MismatchError` with a
  diff when the live schema differs, before creating anything. Never alters or drops.
- `Definition#to_h`: the normalized declaration, with defaults filled in and part types inherited; tarantool-model's
  `Testing::MemoryStorage.from_definition` accepts the definition.
- Depends on `tarantool-client ~> 0.2.0`.
