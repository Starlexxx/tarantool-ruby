# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Comparison do
  let(:space) { Tarantool::Schema::SpaceSpec.build(:codes, engine: :memtx, **codes_declaration).resolve }
  let(:by_note) { Tarantool::Schema::IndexSpec.build(:by_note, { parts: [:note], unique: false }) }

  def declared(raw, alter: [])
    described_class.new(name: :codes, indexes: space.indexes, live: live(raw), space:, alter:)
  end

  def external(raw, index = by_note) = described_class.new(name: :codes, indexes: [index], live: live(raw))

  def live(raw) = raw && Tarantool::Schema::LiveSpace.from_eval(raw)

  it 'plans every index of a missing declared space' do
    comparison = declared(nil)

    expect(comparison).to be_missing_space
    expect(comparison.missing_indexes.map(&:name)).to eq(%i[primary by_code])
    expect(comparison.mismatches).to eq([])
  end

  it 'reports a missing space declared elsewhere' do
    expect(external(nil).mismatches).to eq(['missing'])
  end

  it 'finds nothing when the space matches and ignores undeclared indexes' do
    raw = codes_live.merge('indexes' => codes_live['indexes'] + [live_index(2, 'extra', [[3, 'string', true]])])
    comparison = declared(raw)

    expect(comparison.mismatches).to eq([])
    expect(comparison.missing_indexes).to eq([])
  end

  it 'reports a changed engine' do
    expect(declared(codes_live.merge('engine' => 'vinyl')).mismatches).to eq(['engine: declared memtx, actual vinyl'])
  end

  it 'reports a primary index under another name' do
    raw = codes_live.merge('indexes' => [live_index(0, 'pk', [[1, 'unsigned']], sequence: true)])

    expect(declared(raw).mismatches).to eq(['primary index: declared primary, actual pk'])
  end

  it 'plans fields missing from the live format only when add_field is allowed' do
    raw = codes_live.merge('format' => codes_live['format'].take(2))

    expect(declared(raw).format_additions).to eq([])
    expect(declared(raw, alter: [:add_field]).format_additions.map(&:name)).to eq([:note])
    expect(declared(raw, alter: [:add_field]).mismatches).to eq([])
  end

  it 'plans an index missing from an existing space' do
    raw = codes_live.merge('indexes' => codes_live['indexes'].take(1))

    expect(declared(raw).missing_indexes.map(&:name)).to eq([:by_code])
  end

  it 'resolves an index of a space declared elsewhere against the live format' do
    expect(external(codes_live).missing_indexes.first.parts.first.to_h)
      .to eq(field: :note, type: 'string', is_nullable: true, path: nil)
  end

  it 'reports a field unknown to the live format' do
    index = Tarantool::Schema::IndexSpec.build(:by_x, { parts: [:nope] })

    expect(external(codes_live, index).mismatches).to eq(['index by_x: unknown field nope'])
  end
end
