# Changelog

## 0.3.0 (2026-10-17)

- `Tarantool::Model.default_storage`: a storage, or a Proc called once on first use, for models without one of
  their own.
- Optimistic locking on the `locking_column` attribute (`lock_version` by default): update and destroy compare
  the stored version with the record's and bump it, in a transaction on `Storage::Box`; `StaleObjectError`.
- Storages answer `supports_transactions?`.

## 0.2.0 (2026-10-17)

- `Storage::Box` converts rows with tarantool-client (`as: :row`), by the format of the schema each request ran against, and no longer looks up `space_info` before every operation.
- `Testing::MemoryStorage` (`require 'tarantool/model/testing'`): in-memory storage for application tests that
  keeps the `Storage::Box` or `Storage::Crud` contract, with spaces declared in tarantool-schema's format.
- Depends on `tarantool-client ~> 0.2.0`.

## 0.1.0 (2026-10-16)

First release.

- `Tarantool::Model` mixin on ActiveModel: attributes, validations, callbacks, dirty tracking, JSON.
- `Types::UUID`, `Types::Interval`, `Types::Binary`.
- `Storage::Box` over `Tarantool::Client` and `Pool` with read/write options.
- Persistence: create, save, update, destroy, reload, increment!, decrement!.
- Index queries with keyset pagination: find, find_by, where, limit, after, find_each.
- `Model.transaction` over `Storage::Box`, `TransactionMismatchError` for writes through another storage.
- `Storage::Crud` over `Tarantool::Crud::Client`; raises `Tarantool::Model::Error` when tarantool-crud is not loaded.
- Depends on `tarantool-client ~> 0.1.0`.
