# frozen_string_literal: true

RSpec.describe Tarantool::Model::Key do
  it 'wraps a scalar and keeps an Array' do
    expect([described_class.wrap(1), described_class.wrap([7, 1])]).to eq([[1], [7, 1]])
  end

  it 'wraps a Time instead of splitting it with to_a' do
    time = Time.at(0)

    expect(described_class.wrap(time)).to eq([time])
  end
end
