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

  it 'reports whether fail_all recorded the failure' do
    first = pending.fail_all(Tarantool::ConnectionError.new('lost'))
    second = pending.fail_all(Tarantool::ClientClosedError.new('closed'))

    expect([first, second]).to eq([true, false])
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

  it 'delivers pushes without completing the request' do
    sync, future = pending.register
    pending.push(sync, :progress)
    pending.resolve(sync, :response)
    messages = []

    expect(future.value(1) { |message| messages << message }).to eq(:response)
    expect(messages).to eq([:progress])
  end

  it 'ignores pushes for unknown syncs' do
    expect { pending.push(42, :progress) }.not_to raise_error
  end

  describe '#wait_empty' do
    it 'returns true at once without requests in flight' do
      expect(pending.wait_empty(1)).to be(true)
    end

    it 'returns false when a request is still in flight at the deadline' do
      pending.register

      expect(pending.wait_empty(0.01)).to be(false)
    end

    it 'wakes up when the last request is deleted' do
      sync, = pending.register
      waiter = Thread.new { pending.wait_empty(1) }
      Thread.pass until waiter.status == 'sleep'
      pending.delete(sync)

      expect(waiter.value).to be(true)
    end

    it 'wakes up when the requests are failed' do
      pending.register
      waiter = Thread.new { pending.wait_empty(1) }
      Thread.pass until waiter.status == 'sleep'
      pending.fail_all(Tarantool::ConnectionError.new('lost'))

      expect(waiter.value).to be(true)
    end
  end

  it 'counts the requests in flight' do
    sync, = pending.register
    pending.register
    pending.delete(sync)

    expect(pending.size).to eq(1)
  end
end
