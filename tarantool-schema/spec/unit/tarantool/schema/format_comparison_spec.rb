# frozen_string_literal: true

RSpec.describe Tarantool::Schema::FormatComparison do
  let(:declared) { Tarantool::Schema::SpaceSpec.build(:codes, engine: :memtx, **codes_declaration).format }

  def comparison(format, declared: self.declared, add_field: false)
    live = Tarantool::Schema::LiveSpace.from_eval(codes_live.merge('format' => format)).format

    described_class.new(declared, live, add_field:)
  end

  def mismatches(format) = comparison(format).mismatches

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
    expect(comparison(codes_live['format'].take(2)).additions).to eq([])
  end

  context 'with add_field' do
    let(:with_flag) do
      format = [*codes_declaration[:format], { name: :flag, type: :unsigned }]
      Tarantool::Schema::SpaceSpec.build(:codes, engine: :memtx, **codes_declaration.merge(format:)).format
    end

    it 'plans nullable fields past a matching live prefix' do
      comparison = comparison(codes_live['format'].take(2), add_field: true)

      expect(comparison.mismatches).to eq([])
      expect(comparison.additions.map(&:name)).to eq([:note])
    end

    it 'keeps the count mismatch and names a field that is not nullable' do
      comparison = comparison(codes_live['format'].take(2), declared: with_flag, add_field: true)

      expect(comparison.mismatches).to eq(['format: declared 4 fields, actual 2',
                                           'field 4 flag: must be is_nullable: true to be added'])
      expect(comparison.additions).to eq([])
    end

    it 'keeps a longer live format as a mismatch' do
      format = [*codes_live['format'], { 'name' => 'extra', 'type' => 'string', 'is_nullable' => true }]

      expect(comparison(format, add_field: true).mismatches).to eq(['format: declared 3 fields, actual 4'])
    end

    it 'plans nothing when the live prefix differs' do
      format = [codes_live['format'].first, { 'name' => 'code', 'type' => 'unsigned' }]
      comparison = comparison(format, add_field: true)

      expect(comparison.mismatches).to eq(['format: declared 3 fields, actual 2',
                                           'field 2 code: type declared string, actual unsigned'])
      expect(comparison.additions).to eq([])
    end
  end
end
