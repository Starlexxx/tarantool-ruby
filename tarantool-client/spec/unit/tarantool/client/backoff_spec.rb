# frozen_string_literal: true

RSpec.describe Tarantool::Client::Backoff do
  subject(:backoff) { described_class.new(base: 0.1, max: 5, random:) }

  let(:random) { instance_double(Random, rand: 0.5) }

  it 'scales a random fraction of the exponential delay' do
    expect([0, 1, 3].map { |attempt| backoff.delay(attempt) })
      .to match([be_within(1e-9).of(0.05), be_within(1e-9).of(0.1), be_within(1e-9).of(0.4)])
  end

  it 'caps the delay at max' do
    expect(backoff.delay(10)).to eq(2.5)
  end

  it 'stays capped for huge attempt numbers' do
    expect(backoff.delay(1_000_000)).to eq(2.5)
  end

  it 'draws delays between zero and the cap' do
    delays = Array.new(50) { described_class.new(base: 0.1, max: 5).delay(2) }

    expect(delays).to all(be_between(0, 0.4))
  end
end
