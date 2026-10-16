# frozen_string_literal: true

RSpec.describe Tarantool::Schema::LiveSpace do
  subject(:live) { described_class.from_eval(codes_live) }

  it 'reads the format with defaults filled in' do
    expect(live.format.first).to eq(Tarantool::Schema::FieldSpec.new(name: :id, type: 'unsigned', is_nullable: false))
  end

  it 'downcases index types and names parts by field' do
    by_code = live.index(:by_code)

    expect(by_code.type).to eq('tree')
    expect(by_code.parts).to eq(
      [Tarantool::Schema::PartSpec.new(field: :code, type: 'string', is_nullable: false, path: nil)]
    )
  end

  it 'finds the primary index by id' do
    expect(live.primary.name).to eq(:primary)
  end

  it 'maps format type aliases' do
    raw = codes_live.merge(
      'format' => [{ 'name' => 'id', 'type' => 'unsigned' }, { 'name' => 'code', 'type' => 'str' }]
    )

    expect(described_class.from_eval(raw).format.last.type).to eq('string')
  end

  it 'names a part beyond the format by its field number' do
    raw = codes_live.merge('indexes' => [live_index(0, 'primary', [[5, 'unsigned']])])

    expect(described_class.from_eval(raw).primary.parts.first.field).to eq(:'#5')
  end

  it 'reads an empty format and no indexes' do
    space = described_class.from_eval('engine' => 'memtx', 'format' => {}, 'indexes' => {})

    expect([space.format, space.indexes]).to eq([[], []])
  end
end
