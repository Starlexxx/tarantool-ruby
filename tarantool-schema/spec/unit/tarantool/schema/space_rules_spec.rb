# frozen_string_literal: true

RSpec.describe Tarantool::Schema::SpaceRules do
  def check(engine: :memtx, format: codes_declaration[:format], indexes: codes_declaration[:indexes])
    space = Tarantool::Schema::SpaceSpec.build(:codes, format:, indexes:, engine:)

    described_class.check(space.resolve)
  end

  it 'returns a valid space' do
    expect(check.name).to eq(:codes)
  end

  it 'requires an index' do
    expect { check(indexes: []) }.to raise_error(ArgumentError, 'space codes: at least one index is required')
  end

  it 'rejects an rtree or bitset primary index' do
    expect { check(indexes: [{ name: :pk, parts: [:id], type: :bitset, unique: false }]) }
      .to raise_error(ArgumentError, 'space codes: primary index pk can not be bitset')
  end

  it 'requires a unique primary index' do
    expect { check(indexes: [{ name: :pk, parts: [:id], unique: false }]) }
      .to raise_error(ArgumentError, 'space codes: primary index pk must be unique')
  end

  it 'rejects nullable primary key parts' do
    expect { check(indexes: [{ name: :pk, parts: [:note] }]) }
      .to raise_error(ArgumentError, 'space codes: primary index pk: part note can not be nullable')
  end

  it 'allows a sequence only on the primary index' do
    indexes = [{ name: :pk, parts: [:id] }, { name: :by_code, parts: [:code], sequence: true }]

    expect { check(indexes:) }
      .to raise_error(ArgumentError, 'space codes: index by_code: sequence is only allowed on the primary index')
  end

  it 'needs a single unsigned or integer part for a sequence' do
    expect { check(indexes: [{ name: :pk, parts: [:code], sequence: true }]) }
      .to raise_error(ArgumentError, 'space codes: index pk: sequence needs a single unsigned or integer part')
  end

  it 'allows only tree indexes in vinyl' do
    indexes = [{ name: :pk, parts: [:id] }, { name: :by_code, parts: [:code], type: :hash }]

    expect { check(engine: :vinyl, indexes:) }
      .to raise_error(ArgumentError, 'space codes: vinyl supports only tree indexes, got by_code')
  end

  it 'rejects a hash index on a field whose type defaults to any' do
    format = codes_declaration[:format] + [{ name: :meta }]
    indexes = [{ name: :pk, parts: [:id] }, { name: :by_meta, parts: [:meta], type: :hash }]

    expect { check(format:, indexes:) }
      .to raise_error(ArgumentError, 'space codes: index by_meta: part meta of type any can not be indexed by hash')
  end

  it 'rejects a hash index on a field nullable by its format' do
    indexes = [{ name: :pk, parts: [:id] }, { name: :by_note, parts: [:note], type: :hash }]

    expect { check(indexes:) }
      .to raise_error(ArgumentError, 'space codes: index by_note: hash index can not have nullable part note')
  end
end
