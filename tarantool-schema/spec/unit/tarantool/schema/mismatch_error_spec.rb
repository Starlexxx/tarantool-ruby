# frozen_string_literal: true

RSpec.describe Tarantool::Schema::MismatchError do
  subject(:error) do
    described_class.new(
      'codes' => ['engine: declared memtx, actual vinyl', 'index by_code: unique declared true, actual false'],
      'owned' => ['missing']
    )
  end

  it 'groups the diff by space' do
    expect(error.message).to eq(<<~TEXT.chomp)
      schema mismatch:
        space codes:
          engine: declared memtx, actual vinyl
          index by_code: unique declared true, actual false
        space owned:
          missing
    TEXT
  end

  it 'lists every mismatch prefixed with its space' do
    expect(error.mismatches).to eq(
      ['space codes: engine: declared memtx, actual vinyl',
       'space codes: index by_code: unique declared true, actual false', 'space owned: missing']
    )
  end

  it 'is a Tarantool::Error' do
    expect(error).to be_a(Tarantool::Error)
  end
end
