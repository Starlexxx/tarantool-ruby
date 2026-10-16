# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Definition do
  let(:declaration) { codes_declaration }

  it 'is frozen after the block' do
    expect(codes_definition).to be_frozen
  end

  it 'rejects ensure_space after construction' do
    definition = codes_definition
    declared = declaration

    expect { definition.ensure_space(:other, **declared) }.to raise_error(FrozenError)
  end

  it 'rejects a space declared twice' do
    declared = declaration

    expect { described_class.new { 2.times { ensure_space(:codes, **declared) } } }
      .to raise_error(ArgumentError, 'space codes is already declared')
  end

  it 'rejects unsupported space options' do
    declared = declaration

    expect { described_class.new { ensure_space(:codes, **declared, is_sync: true) } }
      .to raise_error(ArgumentError, /unknown keyword: :is_sync/)
  end

  it 'rejects a space without a name' do
    declared = declaration

    expect { described_class.new { ensure_space(nil, **declared) } }
      .to raise_error(ArgumentError, 'space without name')
  end

  it 'rejects an index for a space without a name' do
    expect { described_class.new { ensure_index(nil, :x, parts: [:id]) } }
      .to raise_error(ArgumentError, 'space without name')
  end

  it 'appends ensure_index to a declared space' do
    declared = declaration
    definition = described_class.new do
      ensure_space(:codes, **declared)
      ensure_index(:codes, :by_note, parts: [:note], unique: false)
    end

    expect(definition.to_h[:codes][:indexes].map { |index| index[:name] }).to eq(%i[primary by_code by_note])
  end

  it 'rejects ensure_space after ensure_index for the same space' do
    declared = declaration

    build = lambda do
      described_class.new do
        ensure_index(:codes, :by_note, parts: [:note])
        ensure_space(:codes, **declared)
      end
    end

    expect(&build).to raise_error(ArgumentError, 'space codes: declare it before its ensure_index')
  end

  it 'validates spaces once the block is done' do
    expect { described_class.new { ensure_space(:codes, format: [{ name: :id, type: :unsigned }], indexes: []) } }
      .to raise_error(ArgumentError, 'space codes: at least one index is required')
  end

  it 'rejects a sequence on an index of a space declared elsewhere' do
    expect { described_class.new { ensure_index(:owned, :pk, parts: [:id], sequence: true) } }
      .to raise_error(ArgumentError, /index pk: sequence is only allowed on the primary index/)
  end

  it 'rejects an index declared twice for a space declared elsewhere' do
    expect { described_class.new { 2.times { ensure_index(:owned, :by_name, parts: [:name]) } } }
      .to raise_error(ArgumentError, 'space owned: duplicate index by_name')
  end

  it 'exposes the normalized declaration' do
    definition = described_class.new do
      ensure_space(:tags, format: [{ name: :id, type: :unsigned }],
                          indexes: [{ name: :pk, parts: [:id], sequence: true }])
    end

    part = { field: :id, type: 'unsigned', is_nullable: false, path: nil }
    index = { name: :pk, type: 'tree', unique: true, sequence: true, parts: [part] }
    space = { engine: 'memtx', format: [{ name: :id, type: 'unsigned', is_nullable: false }], indexes: [index] }

    expect(definition.to_h).to eq(tags: space)
  end
end
