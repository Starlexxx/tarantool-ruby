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

  it 'fails waiting futures and refuses new registrations after fail_all' do
    _, future = pending.register
    pending.fail_all(Tarantool::ConnectionError.new('lost'))

    expect { future.value(1) }.to raise_error(Tarantool::ConnectionError, 'lost')
    expect { pending.register }.to raise_error(Tarantool::ConnectionError, 'lost')
  end

  it 'keeps the first failure reason' do
    pending.fail_all(Tarantool::ClientClosedError.new('closed'))
    pending.fail_all(Tarantool::ConnectionError.new('lost'))

    expect { pending.register }.to raise_error(Tarantool::ClientClosedError)
  end
end
