# frozen_string_literal: true

RSpec.describe Tarantool::Client::UUID do
  it 'normalizes to lower case' do
    uuid = described_class.new('F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6')

    expect(uuid.to_s).to eq('f81d4fae-7dec-11d0-a765-00a0c91e6bf6')
  end

  it 'compares by value' do
    expect(described_class['f81d4fae-7dec-11d0-a765-00a0c91e6bf6'])
      .to eq(described_class.new('F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6'))
  end

  it 'rejects a string that is not a canonical uuid', :rbs_untestable do
    expect { described_class.new('f81d4fae7dec11d0a76500a0c91e6bf6') }.to raise_error(ArgumentError, /invalid UUID/)
  end

  it 'rejects non-strings', :rbs_untestable do
    expect { described_class.new(42) }.to raise_error(ArgumentError, /invalid UUID/)
  end

  it 'freezes its value' do
    expect(described_class.new('F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6').value).to be_frozen
  end
end
