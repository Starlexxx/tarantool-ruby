# frozen_string_literal: true

RSpec.describe Tarantool::Model::Testing::MemoryStorage do
  def build(schema, **) = described_class.new({ users: schema }, **)

  def with_index(**index)
    { format: [{ name: :id, type: :unsigned }, { name: :code }], indexes: [{ name: :primary, parts: %i[id] }, index] }
  end

  it 'rejects an unknown behaves_like' do
    expect { build(Schemas::USERS, behaves_like: :sql) }.to raise_error(ArgumentError, /behaves_like/)
  end

  it 'rejects space names that collide as String and Symbol' do
    expect { described_class.new({ users: Schemas::USERS, 'users' => Schemas::USERS }) }
      .to raise_error(ArgumentError, /duplicate names users/)
  end

  it 'rejects unknown keys at every level' do
    expect { build(Schemas::USERS.merge(if_not_exists: true)) }.to raise_error(ArgumentError, /if_not_exists/)
    expect { build(with_index(name: :code, parts: %i[code], collation: 'unicode')) }
      .to raise_error(ArgumentError, /collation/)
    expect { build(with_index(name: :code, parts: [{ field: :code, sort_order: 'desc' }])) }
      .to raise_error(ArgumentError, /sort_order/)
  end

  it 'rejects a space without format or indexes' do
    expect { build({ format: [{ name: :id }] }) }.to raise_error(ArgumentError, /indexes/)
    expect { build({ format: [{ name: :id }], indexes: [] }) }.to raise_error(ArgumentError, /indexes/)
    expect { build({ indexes: [{ name: :primary, parts: %i[id] }] }) }.to raise_error(ArgumentError, /format/)
  end

  it 'rejects non-canonical field and index types' do
    expect { build({ format: [{ name: :id, type: :str }], indexes: [{ name: :primary, parts: %i[id] }] }) }
      .to raise_error(ArgumentError, /str/)
    expect { build(with_index(name: :code, parts: %i[code], type: :rtree)) }.to raise_error(ArgumentError, /rtree/)
  end

  it 'rejects bare field names in format, duplicate names and unknown part fields' do
    expect { build({ format: [:id], indexes: [{ name: :primary, parts: %i[id] }] }) }.to raise_error(ArgumentError)
    expect { build({ format: [{ name: :id }, { name: :id }], indexes: [{ name: :primary, parts: %i[id] }] }) }
      .to raise_error(ArgumentError, /duplicate/)
    expect { build(with_index(name: :code, parts: %i[nope])) }.to raise_error(ArgumentError, /nope/)
  end

  it 'rejects path parts, a non-unique primary and a non-unique hash index' do
    expect { build(with_index(name: :code, parts: [{ field: :code, path: 'a.b' }])) }
      .to raise_error(ArgumentError, /path/)
    expect { build({ format: [{ name: :id }], indexes: [{ name: :primary, parts: %i[id], unique: false }] }) }
      .to raise_error(ArgumentError, /unique/)
    expect { build(with_index(name: :code, parts: %i[code], type: :hash, unique: false)) }
      .to raise_error(ArgumentError, /unique/)
  end

  it 'rejects a nullable part in the primary index, from the part or its field' do
    nullable_id = [{ name: :id, type: :unsigned, is_nullable: true }]
    expect { build({ format: nullable_id, indexes: [{ name: :primary, parts: %i[id] }] }) }
      .to raise_error(ArgumentError, /primary index can not contain nullable parts/)
    nullable_part = [{ name: :primary, parts: [{ field: :id, is_nullable: true }] }]
    expect { build({ format: [{ name: :id }], indexes: nullable_part }) }.to raise_error(ArgumentError, /nullable/)
  end

  it 'rejects a nullable part in a hash index unless the part overrides its field' do
    nullable_code = { format: [{ name: :id, type: :unsigned }, { name: :code, is_nullable: true }],
                      indexes: [{ name: :primary, parts: %i[id] }] }
    hash_on = ->(parts) { nullable_code.merge(indexes: [*nullable_code[:indexes], { name: :c, parts:, type: :hash }]) }

    expect { build(hash_on.call(%i[code])) }.to raise_error(ArgumentError, /hash index does not support nullable parts/)
    expect { build(with_index(name: :c, parts: [{ field: :code, is_nullable: true }], type: :hash)) }
      .to raise_error(ArgumentError, /nullable/)
    expect { build(hash_on.call([{ field: :code, is_nullable: false }])) }.not_to raise_error
  end

  it 'allows a sequence only on a primary index with one unsigned or integer part' do
    expect { build(with_index(name: :code, parts: %i[code], sequence: true)) }.to raise_error(ArgumentError, /sequence/)
    string_format = [{ name: :id, type: :string }]
    string_indexes = [{ name: :primary, parts: %i[id], sequence: true }]
    expect { build({ format: string_format, indexes: string_indexes }) }.to raise_error(ArgumentError, /sequence/)
  end

  describe '#verify' do
    subject(:storage) { build(Schemas::USERS) }

    it 'accepts a model whose attributes and primary key match the format' do
      expect { storage.verify(:users, attributes: %i[id email], primary_key: %i[id]) }.not_to raise_error
    end

    it 'raises SchemaMismatchError like Storage::Box' do
      expect { storage.verify(:users, attributes: %i[id phone], primary_key: %i[id]) }
        .to raise_error(Tarantool::Model::SchemaMismatchError, /phone/)
      expect { storage.verify(:users, attributes: %i[id email], primary_key: %i[email]) }
        .to raise_error(Tarantool::Model::SchemaMismatchError, /primary key/)
    end

    it 'raises Tarantool::SchemaError for an unknown space' do
      expect { storage.verify(:nope, attributes: %i[id], primary_key: %i[id]) }
        .to raise_error(Tarantool::SchemaError, "space 'nope' not found")
    end

    it 'does not look the space up when it behaves like Storage::Crud' do
      expect(build(Schemas::USERS, behaves_like: :crud).verify(:nope, attributes: %i[id], primary_key: %i[id]))
        .to be_nil
    end
  end
end
