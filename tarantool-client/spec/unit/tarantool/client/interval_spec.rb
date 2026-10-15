# frozen_string_literal: true

RSpec.describe Tarantool::Client::Interval do
  it 'defaults every unit to zero and adjust to :none like datetime.interval.new' do
    expect(described_class.new).to have_attributes(
      year: 0, month: 0, week: 0, day: 0, hour: 0, min: 0, sec: 0, nsec: 0, adjust: :none
    )
  end

  it 'takes any subset of units' do
    expect(described_class.new(month: -2, adjust: :last)).to have_attributes(month: -2, day: 0, adjust: :last)
  end

  it 'rejects a Float unit' do
    expect { described_class.new(sec: 1.5) }.to raise_error(ArgumentError, /sec=1\.5/)
  end

  it 'rejects a nil unit' do
    expect { described_class.new(sec: nil) }.to raise_error(ArgumentError, /sec=nil/)
  end

  it 'rejects a String unit' do
    expect { described_class.new(year: '1') }.to raise_error(ArgumentError, /year="1"/)
  end
end
