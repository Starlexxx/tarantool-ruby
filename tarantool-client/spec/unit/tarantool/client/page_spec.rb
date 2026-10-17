# frozen_string_literal: true

RSpec.describe Tarantool::Client::Page do
  subject(:page) { described_class.new(tuples: [[1], [2]], position: 'kgAD') }

  it 'enumerates its tuples' do
    expect(page.map(&:first)).to eq([1, 2])
  end

  it 'reports size and emptiness' do
    expect([page.size, page.empty?]).to eq([2, false])
  end
end
