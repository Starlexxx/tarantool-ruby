# frozen_string_literal: true

RSpec.describe Tarantool::Schema::IndexSpec do
  let(:fields) { { id: Tarantool::Schema::FieldSpec.new(name: :id, type: 'unsigned', is_nullable: false) } }

  it 'rejects a nil name' do
    expect { described_class.build(nil, { parts: [:id] }) }.to raise_error(ArgumentError, 'index without name')
  end

  it 'fills create_index defaults' do
    index = described_class.build(:primary, { parts: [:id] })

    expect([index.type, index.unique, index.sequence]).to eq(['tree', true, false])
  end

  it 'rejects an unknown index type' do
    expect { described_class.build(:pk, { parts: [:id], type: :btree }) }
      .to raise_error(ArgumentError, 'index pk: unknown type "btree"')
  end

  it 'rejects a unique rtree or bitset index' do
    expect { described_class.build(:area, { parts: [:id], type: :rtree }) }
      .to raise_error(ArgumentError, 'index area: rtree index can not be unique, set unique: false')
  end

  it 'rejects an explicitly non-unique hash index' do
    expect { described_class.build(:by_x, { parts: [:id], type: :hash, unique: false }) }
      .to raise_error(ArgumentError, 'index by_x: hash index must be unique')
  end

  it 'rejects a hash index on an explicitly unsupported part type' do
    expect { described_class.build(:by_x, { parts: [{ field: :meta, type: :map }], type: :hash }) }
      .to raise_error(ArgumentError, 'index by_x: part meta of type map can not be indexed by hash')
  end

  it 'rejects an explicitly nullable hash part' do
    part = { field: :note, type: :string, is_nullable: true }

    expect { described_class.build(:by_x, { parts: [part], type: :hash }) }
      .to raise_error(ArgumentError, 'index by_x: hash index can not have nullable part note')
  end

  it 'allows an explicitly nullable tree part' do
    index = described_class.build(:by_x, { parts: [{ field: :note, type: :string, is_nullable: true }] })

    expect(index.parts.first.is_nullable).to be(true)
  end

  it 'requires parts to be a non-empty Array' do
    expect { described_class.build(:pk, { parts: { field: :id } }) }
      .to raise_error(ArgumentError, 'index pk: parts must be a non-empty Array')
  end

  it 'rejects unsupported index options' do
    expect { described_class.build(:pk, { parts: [:id], page_size: 8192 }) }
      .to raise_error(ArgumentError, 'index pk: unsupported :page_size')
  end

  it 'rejects a non-boolean sequence' do
    expect { described_class.build(:pk, { parts: [:id], sequence: 'pk_seq' }) }
      .to raise_error(ArgumentError, 'index pk sequence: expected true or false, got "pk_seq"')
  end

  it 'lists parts referring to unknown fields' do
    expect(described_class.build(:pk, { parts: %i[id code] }).unknown_fields(fields)).to eq([:code])
  end

  it 'resolves parts against the fields' do
    expect(described_class.build(:pk, { parts: [:id] }).resolve(fields).to_h).to eq(
      name: :pk, type: 'tree', unique: true, sequence: false,
      parts: [{ field: :id, type: 'unsigned', is_nullable: false, path: nil }]
    )
  end

  it 'builds create_index options' do
    expect(described_class.build(:pk, { parts: [:id], sequence: true }).resolve(fields).to_lua).to eq(
      'type' => 'tree', 'unique' => true, 'sequence' => true,
      'parts' => [{ 'field' => 'id', 'type' => 'unsigned', 'is_nullable' => false }]
    )
  end
end
