# Changelog

## 0.1.0 (unreleased)

First release.

- `Tarantool::Model` mixin on ActiveModel: attributes, validations, callbacks, dirty tracking, JSON.
- `Types::UUID`, `Types::Interval`, `Types::Binary`.
- `Storage::Box` over `Tarantool::Client` and `Pool` with read/write options.
- Persistence: create, save, update, destroy, reload, increment!, decrement!.
- Index queries with keyset pagination: find, find_by, where, limit, after, find_each.
- `Model.transaction` over `Storage::Box`, `TransactionMismatchError` for writes through another storage.
- `Storage::Crud` over `Tarantool::Crud::Client`; raises `Tarantool::Model::Error` when tarantool-crud is not loaded.
- Depends on `tarantool-client ~> 0.1.0`.
