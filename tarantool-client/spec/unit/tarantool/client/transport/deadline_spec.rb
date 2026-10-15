# frozen_string_literal: true

RSpec.describe Tarantool::Client::Transport::Deadline do
  it 'never expires without a timeout' do
    expect(described_class.remaining(described_class.after(nil))).to be_nil
  end

  it 'counts down from the timeout' do
    expect(described_class.remaining(described_class.after(5))).to be_between(4, 5)
  end

  it 'does not go below zero once passed' do
    expect(described_class.remaining(described_class.after(-1))).to eq(0)
  end
end
