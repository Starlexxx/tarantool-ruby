# frozen_string_literal: true

RSpec.describe Tarantool::Client::Transport::Future do
  subject(:future) { described_class.new }

  it 'returns the resolved value' do
    future.resolve(:ok)

    expect(future.value(1)).to eq(:ok)
  end

  it 'raises a copy of the rejection error' do
    error = Tarantool::ConnectionError.new('lost')
    future.reject(error)

    expect { future.value(1) }.to raise_error(Tarantool::ConnectionError, 'lost') { |raised| expect(raised).not_to be(error) }
  end

  it 'raises TimeoutError when nothing arrives in time' do
    expect { future.value(0.01) }.to raise_error(Tarantool::TimeoutError)
  end

  it 'wakes up a waiter blocked in another thread' do
    Thread.new { future.resolve(:late) }

    expect(future.value(1)).to eq(:late)
  end
end
