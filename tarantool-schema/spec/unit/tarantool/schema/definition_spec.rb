# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Definition do
  let(:declaration) { codes_declaration }

  describe '.from_live' do
    it 'declares every user space as the server has it' do
      client = FakeClient.new('codes' => codes_live, 'users' => codes_live)
      definition = described_class.from_live(client)

      expect(definition.to_h.keys).to eq(%i[codes users])
      expect(definition.to_h[:codes]).to eq(codes_definition.to_h[:codes])
    end

    it 'has nothing to plan against the server it was read from' do
      client = FakeClient.new('codes' => codes_live)

      expect(described_class.from_live(client).plan(client)).to eq([])
    end

    it 'reads only the named spaces' do
      client = FakeClient.new('codes' => codes_live, 'users' => codes_live)

      expect(described_class.from_live(client, only: [:users]).to_h.keys).to eq([:users])
    end

    it 'reads the grants on each space' do
      client = FakeClient.new('codes' => codes_live)
      client.masks['codes'] = { 'app' => 3, 'ops' => 4 }

      expect(described_class.from_live(client).grants)
        .to eq([{ user: :app, privileges: %w[read write], space: :codes }])
      expect(described_class.from_live(client).plan(client)).to eq([])
    end

    it 'rejects a named space that does not exist' do
      expect { described_class.from_live(FakeClient.new, only: [:nope]) }
        .to raise_error(ArgumentError, 'space nope: not found')
    end
  end

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

  describe '#grant' do
    it 'normalizes grants in declaration order' do
      declared = declaration
      definition = described_class.new do
        ensure_space(:codes, **declared)
        grant(:reporting, :read, on: :codes)
        grant('app', %i[write read], on: 'codes')
      end

      expect(definition.grants).to eq([{ user: :reporting, privileges: %w[read], space: :codes },
                                       { user: :app, privileges: %w[read write], space: :codes }])
    end

    it 'rejects the same grantee twice on one space' do
      expect { described_class.new { 2.times { grant(:app, :read, on: :codes) } } }
        .to raise_error(ArgumentError, 'grant app on codes is already declared')
    end

    it 'rejects an unknown privilege' do
      expect { described_class.new { grant(:app, :execute, on: :codes) } }
        .to raise_error(ArgumentError, /grant app on codes: unknown privilege :execute/)
    end

    it 'keeps grants out of to_h' do
      declared = declaration
      definition = described_class.new do
        ensure_space(:codes, **declared)
        grant(:app, :read, on: :codes)
      end

      expect(definition.to_h.keys).to eq([:codes])
      expect(definition.to_h[:codes].keys).to eq(%i[engine format indexes])
    end
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
