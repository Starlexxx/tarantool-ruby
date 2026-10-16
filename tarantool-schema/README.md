# tarantool-schema

Idempotent schema declaration for Tarantool 2.11+ and 3.x, meant for deploys. You declare spaces, indexes and
primary key sequences in Ruby; `apply` creates whatever is missing and checks everything that already exists.
If the live schema differs from the declaration, it raises an error with a diff and creates nothing. It never
alters or drops anything: changing a field type or rebuilding an index is a migration and is out of scope.

## Installation

Requirements: Ruby >= 3.2, Tarantool 2.11+ or 3.x.

```ruby
gem 'tarantool-schema'
```

```ruby
require 'tarantool/schema'
```

## Declaring a schema

```ruby
module MyApp
  SCHEMA = Tarantool::Schema::Definition.new do
    ensure_space :codes, engine: :memtx,
      format: [
        { name: :id, type: :unsigned },
        { name: :code, type: :string },
        { name: :expires_at, type: :unsigned, is_nullable: true }
      ],
      indexes: [
        { name: :primary, parts: [:id], sequence: true },
        { name: :by_code, parts: [:code] }
      ]

    ensure_index :codes, :by_expiry, parts: [:expires_at], unique: false
  end
end
```

The block runs with the definition as `self`, then the definition is frozen: calling `ensure_*` later raises
`FrozenError`, and loading the file again builds a new definition instead of growing the old one.

- `ensure_space(name, format:, indexes:, engine: :memtx)`. `format` uses Tarantool's own keys: `name`, `type`
  (omitted means `any`), `is_nullable` (default false). `indexes` are in declaration order; the first one is the
  primary key.
- Index keys: `name`, `parts`, `unique` (default true), `type` (`tree` by default, `hash`, `bitset`, `rtree`),
  `sequence` (default false). A part is a field name or `{ field:, type:, is_nullable:, path: }`. A part's type
  and nullability default to the field's; a part with a JSON `path` must declare its type.
- `ensure_index(space, name, **options)` adds an index to a space declared in the same definition. For a space
  owned by someone else it only adds the index: the space must already exist, and part types come from its
  live format.

### Validation

These raise `ArgumentError` while the definition is built, before anything reaches the server:

- a space declared twice, or declared after an `ensure_index` for it; a duplicate field or index name;
- unknown keys anywhere, including the unsupported options listed below;
- type aliases or unknown types. Only canonical names are accepted: `any unsigned string integer number double
  boolean decimal uuid datetime interval varbinary scalar array map`. Use `string`, not `str`;
- a part that refers to a field missing from the format;
- vinyl spaces with anything but `tree` indexes;
- unique `rtree`/`bitset` indexes, and `rtree`/`bitset`, non-unique or nullable primary keys;
- `sequence: true` anywhere except a primary key with exactly one `unsigned` or `integer` part.

### Not supported

Declaring any of these raises `ArgumentError`, so nobody assumes they were applied:

- space: `is_sync`, `temporary`, `is_local`, `field_count`, `id`, `user`, `constraint`, `foreign_key`;
- field: `default`, `default_func`, `constraint`, `foreign_key`, `collation`;
- index: `id`, `hint`, `func`, `dimension`, `distance`, vinyl tuning (`page_size`, `range_size`,
  `run_count_per_level`, `run_size_ratio`, `bloom_fpr`);
- part: `collation`, `sort_order`, `exclude_null`.

Options that are set on a live space but that you did not declare are ignored when comparing.

## Applying

```ruby
client = Tarantool::Client.new(ENV.fetch('TARANTOOL_ADMIN_URI'))

MyApp::SCHEMA.plan(client)  # => ["index codes.by_expiry"], writes nothing
MyApp::SCHEMA.apply(client) # => ["index codes.by_expiry"]
MyApp::SCHEMA.apply(client) # => []
```

Connect to the read-write instance. `apply`:

1. reads every declared space (one `eval` per space, with the name passed as an argument);
2. compares it with the declaration and collects the differences across all spaces;
3. if there are any, raises `Tarantool::Schema::MismatchError` and creates nothing;
4. creates the missing spaces and indexes in declaration order, with `if_not_exists` so two deploys racing each
   other do not fail;
5. reads everything again and raises `MismatchError` if something is still missing or differs, for example
   when another deploy created the space differently in the meantime.

Each space and index is created with its own `eval`, so if one fails partway through (for example a privilege
missing for a later index), the ones created before it stay; running `apply` again is idempotent and picks up
where it left off.

Comparison is strict about what you declared: engine; format (field count, and for each position the name,
type and nullability); the primary index name; and for each declared index its type, uniqueness, sequence and
parts. Indexes in the live space that you did not declare are ignored. Type aliases in a live format (`str`,
`num`) count as their canonical names.

```
schema mismatch:
  space codes:
    engine: declared memtx, actual vinyl
    field 2 code: type declared string, actual unsigned
    index by_code: unique declared true, actual false
```

`MismatchError#mismatches` returns the same lines as an Array, each prefixed with `space <name>: `.

## Rake

```ruby
namespace :tarantool do
  namespace :schema do
    def with_schema_client
      require 'tarantool/schema'
      require_relative 'config/tarantool_schema' # defines MyApp::SCHEMA
      client = Tarantool::Client.new(ENV.fetch('TARANTOOL_ADMIN_URI'))
      yield client
    ensure
      client&.close
    end

    desc 'Show what tarantool:schema:apply would create; fail on drift'
    task :check do
      with_schema_client { |client| puts MyApp::SCHEMA.plan(client) }
    end

    desc 'Create missing Tarantool spaces and indexes; fail on drift'
    task :apply do
      with_schema_client { |client| puts MyApp::SCHEMA.apply(client) }
    end
  end
end
```

## Privileges

The deploy user needs these privileges (tested on 2.11 and 3.x):

| Privilege | 2.11 | 3.x |
|---|---|---|
| eval | `execute` on `universe` | `execute` on `lua_eval` |
| create spaces | `create` on `space` | same |
| primary key sequences | `create` on `sequence` | same |
| system spaces | `read,write` on spaces `_space`, `_index`, `_sequence`, `_space_sequence` | same |

```lua
box.schema.user.create('deployer', {password = '...'})
box.schema.user.grant('deployer', 'execute', 'lua_eval')      -- 2.11: 'execute', 'universe'
box.schema.user.grant('deployer', 'create', 'space')
box.schema.user.grant('deployer', 'create', 'sequence')
for _, name in ipairs({'_space', '_index', '_sequence', '_space_sequence'}) do
  box.schema.user.grant('deployer', 'read,write', 'space', name)
end
```

On 2.11, only `admin` can grant privileges on `universe`; a `super` user cannot. Adding an index to a space
owned by another user also needs `alter` on that space. The simplest setup is a dedicated deploy user that owns
the application spaces, or one with the `super` role.

## Sharing the declaration with tests

`Definition#to_h` returns the normalized declaration: names as Symbols, types as Strings, every default filled
in, part types inherited, and `ensure_index` entries merged into their spaces. Use it to build an in-memory
test double or any other representation of the schema from the same declaration used to deploy it.

```ruby
MyApp::SCHEMA.to_h
# => { codes: { engine: 'memtx',
#               format: [{ name: :id, type: 'unsigned', is_nullable: false }, ...],
#               indexes: [{ name: :primary, type: 'tree', unique: true, sequence: true,
#                           parts: [{ field: :id, type: 'unsigned', is_nullable: false, path: nil }] }, ...] } }
```

## Errors

`Tarantool::Schema::MismatchError < Tarantool::Schema::Error < Tarantool::Error`. Server errors such as access
denied or a read-only instance are raised unchanged as `Tarantool::ServerError`.

## Development

```sh
cd tarantool-client && podman compose up -d --wait   # from the main checkout only; 2.11 on 3301, 3.x on 3302
cd ../tarantool-schema
bundle exec rspec                                     # unit
INTEGRATION=1 TARANTOOL_URI=tcp://app:secret@localhost:3301 bundle exec rspec
INTEGRATION=1 TARANTOOL_URI=tcp://app:secret@localhost:3302 bundle exec rspec
```

## License

MIT, see [LICENSE](LICENSE).
