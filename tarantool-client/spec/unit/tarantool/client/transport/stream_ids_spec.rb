# frozen_string_literal: true

RSpec.describe Tarantool::Client::Transport::StreamIds do
  subject(:stream_ids) { described_class.new }

  it 'issues increasing ids starting from 1' do
    expect([stream_ids.next, stream_ids.next]).to eq([1, 2])
  end

  it 'hands out unique ids across threads' do
    ids = Array.new(4) { Thread.new { stream_ids.next } }.map(&:value)

    expect(ids.sort).to eq([1, 2, 3, 4])
  end
end
