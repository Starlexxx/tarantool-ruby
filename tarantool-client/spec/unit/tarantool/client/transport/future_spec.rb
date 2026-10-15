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

  it 'yields pushed messages in order before returning the value' do
    future.push(:first)
    future.push(:second)
    future.resolve(:done)
    messages = []

    expect(future.value(1) { |message| messages << message }).to eq(:done)
    expect(messages).to eq(%i[first second])
  end

  it 'skips pushed messages when no block is given' do
    future.push(:first)
    future.resolve(:done)

    expect(future.value(1)).to eq(:done)
  end

  it 'counts pushes against one timeout' do
    Thread.new do
      10.times do
        future.push(:tick)
        sleep 0.02
      end
    end
    started = Tarantool::Client::Transport::Deadline.now

    expect { future.value(0.05) { nil } }.to raise_error(Tarantool::TimeoutError, 'no response within 0.05s')
    expect(Tarantool::Client::Transport::Deadline.now - started).to be < 0.15
  end
end
