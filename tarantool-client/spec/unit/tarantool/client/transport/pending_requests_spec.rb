# frozen_string_literal: true

RSpec.describe Tarantool::Client::Transport::PendingRequests do
  subject(:pending) { described_class.new }

  it 'issues increasing syncs' do
    expect([pending.register.first, pending.register.first]).to eq([1, 2])
  end

  it 'resolves the future registered under a sync' do
    sync, future = pending.register
    pending.resolve(sync, :response)

    expect(future.value(1)).to eq(:response)
  end

  it 'ignores responses for unknown syncs' do
    expect { pending.resolve(42, :response) }.not_to raise_error
  end

  it 'does not deliver a response once the sync has been deleted' do
    sync, future = pending.register
    pending.delete(sync)
    pending.resolve(sync, :response)

    expect { future.value(0.01) }.to raise_error(Tarantool::TimeoutError)
  end

  it 'fails waiting futures and refuses new registrations after fail_all' do
    _, future = pending.register
    pending.fail_all(Tarantool::ConnectionError.new('lost'))

    expect { future.value(1) }.to raise_error(Tarantool::ConnectionError, 'lost')
    expect { pending.register }.to raise_error(Tarantool::ConnectionError, 'lost')
  end

  it 'wakes a waiter blocked in another thread when fail_all is called' do
    _, future = pending.register
    thread = Thread.new do
      future.value(1)
    rescue Tarantool::ConnectionError => e
      e.class
    end

    pending.fail_all(Tarantool::ConnectionError.new('lost'))

    expect(thread.value).to eq(Tarantool::ConnectionError)
  end

  it 'keeps the first failure reason' do
    pending.fail_all(Tarantool::ClientClosedError.new('closed'))
    pending.fail_all(Tarantool::ConnectionError.new('lost'))

    expect { pending.register }.to raise_error(Tarantool::ClientClosedError)
  end

  it 'exposes the stored failure' do
    pending.fail_all(Tarantool::ClientClosedError.new('closed'))

    expect(pending.failure).to be_a(Tarantool::ClientClosedError)
  end
end
