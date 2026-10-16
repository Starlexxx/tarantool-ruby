# frozen_string_literal: true

RSpec.describe Tarantool::Schema::IndexComparison do
  let(:declared) { Tarantool::Schema::SpaceSpec.build(:codes, engine: :memtx, **codes_declaration).resolve.indexes.last }

  def mismatches(live_by_code)
    live = Tarantool::Schema::LiveSpace.from_eval(codes_live.merge('indexes' => [live_by_code])).index(:by_code)

    described_class.new(declared, live).mismatches
  end

  it 'finds nothing when indexes match' do
    expect(mismatches(live_index(1, 'by_code', [[2, 'string']]))).to eq([])
  end

  it 'reports a changed attribute' do
    expect(mismatches(live_index(1, 'by_code', [[2, 'string']], unique: false)))
      .to eq(['index by_code: unique declared true, actual false'])
  end

  it 'reports a changed type and sequence' do
    expect(mismatches(live_index(1, 'by_code', [[2, 'string']], type: 'HASH', sequence: true)))
      .to eq(['index by_code: type declared tree, actual hash', 'index by_code: sequence declared false, actual true'])
  end

  it 'reports changed parts' do
    expect(mismatches(live_index(1, 'by_code', [[3, 'string', true]])))
      .to eq(['index by_code: parts declared code string, actual note string nullable'])
  end
end
