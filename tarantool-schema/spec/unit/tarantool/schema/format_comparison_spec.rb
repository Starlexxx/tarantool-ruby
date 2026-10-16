# frozen_string_literal: true

RSpec.describe Tarantool::Schema::FormatComparison do
  let(:declared) { Tarantool::Schema::SpaceSpec.build(:codes, engine: :memtx, **codes_declaration).format }

  def mismatches(format)
    live = Tarantool::Schema::LiveSpace.from_eval(codes_live.merge('format' => format)).format

    described_class.new(declared, live).mismatches
  end

  it 'finds nothing when formats match' do
    expect(mismatches(codes_live['format'])).to eq([])
  end

  it 'reports a changed type' do
    format = codes_live['format'].dup.tap { |f| f[1] = { 'name' => 'code', 'type' => 'unsigned' } }

    expect(mismatches(format)).to eq(['field 2 code: type declared string, actual unsigned'])
  end

  it 'reports changed nullability' do
    format = codes_live['format'].dup.tap { |f| f[2] = { 'name' => 'note', 'type' => 'string' } }

    expect(mismatches(format)).to eq(['field 3 note: is_nullable declared true, actual false'])
  end

  it 'reports a different field count' do
    expect(mismatches(codes_live['format'].take(2))).to eq(['format: declared 3 fields, actual 2'])
  end
end
