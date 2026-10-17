# frozen_string_literal: true

RSpec.describe Tarantool::Schema::LiveDefinition do
  def arguments(raw, name = :codes) = described_class.arguments(name, Tarantool::Schema::LiveSpace.from_eval(raw))

  it 'turns a live space into ensure_space arguments' do
    expect(arguments(codes_live)).to eq(
      engine: 'memtx',
      format: [{ name: :id, type: 'unsigned', is_nullable: false }, { name: :code, type: 'string', is_nullable: false },
               { name: :note, type: 'string', is_nullable: true }],
      indexes: [{ name: :primary, type: 'tree', unique: true, sequence: true, parts: [:id] },
                { name: :by_code, type: 'tree', unique: true, sequence: false, parts: [:code] }]
    )
  end

  it 'keeps the engine and index type as read' do
    raw = codes_live.merge('engine' => 'vinyl', 'indexes' => [live_index(0, 'primary', [[1, 'unsigned']])])

    primary = { name: :primary, type: 'tree', unique: true, sequence: false, parts: [:id] }

    expect(arguments(raw).values_at(:engine, :indexes)).to eq(['vinyl', [primary]])
  end

  it 'spells out a part whose type or nullability differs from the field' do
    raw = codes_live.merge('indexes' => [live_index(0, 'primary', [[1, 'unsigned']]),
                                         live_index(1, 'by_code', [[2, 'scalar'], [3, 'string', false]])])

    expect(arguments(raw)[:indexes].last[:parts]).to eq([{ field: :code, type: 'scalar' },
                                                         { field: :note, is_nullable: false }])
  end

  it 'spells out a path part with its type' do
    index = live_index(1, 'by_x', [[3, 'string', true]], unique: false)
    index['parts'].first['path'] = 'x'
    raw = codes_live.merge('indexes' => [live_index(0, 'primary', [[1, 'unsigned']]), index])

    expect(arguments(raw)[:indexes].last[:parts]).to eq([{ field: :note, type: 'string', path: 'x' }])
  end

  it 'rejects a functional index' do
    raw = codes_live.merge('indexes' => [live_index(0, 'primary', [[1, 'unsigned']]),
                                         live_index(1, 'by_hash', [[1, 'unsigned']], func: true)])

    expect { arguments(raw) }.to raise_error(ArgumentError, 'space codes: index by_hash is functional, not supported')
  end

  it 'rejects a part beyond the format' do
    raw = codes_live.merge('indexes' => [live_index(0, 'primary', [[5, 'unsigned']])])

    expect { arguments(raw) }.to raise_error(ArgumentError, 'space codes: index primary: part #5 is beyond the format')
  end
end
