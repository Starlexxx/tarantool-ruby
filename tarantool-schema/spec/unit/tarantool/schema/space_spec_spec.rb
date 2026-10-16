# frozen_string_literal: true

RSpec.describe Tarantool::Schema::SpaceSpec do
  def build(**overrides)
    described_class.build(:codes, **codes_declaration, engine: :memtx, **overrides)
  end

  it 'normalizes the declaration' do
    hash = build.resolve.to_h

    expect(hash.slice(:engine)).to eq(engine: 'memtx')
    expect(hash[:format].first).to eq(name: :id, type: 'unsigned', is_nullable: false)
    expect(hash[:indexes].map { |index| index[:name] }).to eq(%i[primary by_code])
  end

  it 'rejects a nil name' do
    expect { described_class.build(nil, **codes_declaration, engine: :memtx) }
      .to raise_error(ArgumentError, 'space without name')
  end

  it 'rejects an unknown engine' do
    expect { build(engine: :sophia) }.to raise_error(ArgumentError, 'space codes: unknown engine "sophia"')
  end

  it 'rejects duplicate fields' do
    format = [{ name: :id, type: :unsigned }, { name: :id, type: :string }]

    expect { build(format:) }.to raise_error(ArgumentError, 'space codes: duplicate field id')
  end

  it 'rejects duplicate indexes' do
    indexes = [{ name: :primary, parts: [:id] }, { name: :primary, parts: [:code] }]

    expect { build(indexes:) }.to raise_error(ArgumentError, 'space codes: duplicate index primary')
  end

  it 'rejects an index without a name' do
    expect { build(indexes: [{ parts: [:id] }]) }.to raise_error(ArgumentError, 'space codes: index without name')
  end

  it 'rejects parts referring to unknown fields when resolved' do
    space = build(indexes: [{ name: :primary, parts: [:nope] }])

    expect { space.resolve }.to raise_error(ArgumentError, 'space codes: index primary: unknown field nope')
  end

  it 'inherits part types from the format when resolved' do
    expect(build.resolve.indexes.last.parts.first.type).to eq('string')
  end

  it 'builds space.create options' do
    expect(build(format: [{ name: :id, type: :unsigned }], indexes: []).to_lua)
      .to eq('engine' => 'memtx', 'format' => [{ 'name' => 'id', 'type' => 'unsigned', 'is_nullable' => false }])
  end
end
