# frozen_string_literal: true

RSpec.describe Tarantool::Client::Watchers do
  subject(:watchers) { described_class.new(connection, timeout: 1) }

  let(:connection) { instance_double(Tarantool::Client::Transport::Connection) }
  let(:sent) { Thread::Queue.new }
  let(:events) { Thread::Queue.new }

  def watch_request(key) = Tarantool::Client::Protocol::Requests::Watch.new(key:)
  def unwatch_request(key) = Tarantool::Client::Protocol::Requests::Unwatch.new(key:)
  def collect(key) = watchers.add(key, ->(*event) { events << event })
  def sent_so_far = Array.new(sent.size) { sent.pop }

  def collect_and_hold(key, hold_at, hold)
    watchers.add(key, lambda { |k, value|
      events << [k, value]
      hold.pop(timeout: 1) if value == hold_at
    })
  end

  before { allow(connection).to receive(:notify) { |request, **| sent << request } }
  after { watchers.close }

  it 'sends WATCH for the first watcher of a key only' do
    2.times { collect('k') }

    expect(sent_so_far).to eq([watch_request('k')])
  end

  it 'runs a deferred job without any watcher' do
    watchers.defer { events << :ran }

    expect(events.pop(timeout: 1)).to eq(:ran)
  end

  it 'runs callbacks off the thread that dispatched the event' do
    watchers.add('k', ->(_key, _value) { events << Thread.current })
    watchers.dispatch('k', 1)

    expect(events.pop(timeout: 1)).not_to eq(Thread.current)
  end

  it 'delivers an event to every watcher of its key' do
    2.times { collect('k') }
    watchers.dispatch('k', 1)

    expect(Array.new(2) { events.pop(timeout: 1) }).to eq([['k', 1], ['k', 1]])
  end

  it 'acknowledges an event with WATCH once the callbacks returned' do
    release = Thread::Queue.new
    watchers.add('k', ->(_key, _value) { release.pop(timeout: 1) })
    sent.pop(timeout: 1)
    watchers.dispatch('k', 1)

    expect(sent.pop(timeout: 0.1)).to be_nil
    release << :go
    expect(sent.pop(timeout: 1)).to eq(watch_request('k'))
  end

  it 'ignores events for keys nobody watches' do
    collect('k')
    watchers.dispatch('other', 1)
    watchers.dispatch('k', 2)

    expect(events.pop(timeout: 1)).to eq(['k', 2])
    expect(Array.new(2) { sent.pop(timeout: 1) }).to eq([watch_request('k'), watch_request('k')])
    expect(sent.pop(timeout: 0.05)).to be_nil
  end

  it 'gives a watcher added later the last value of its key' do
    collect('k')
    watchers.dispatch('k', 1)
    events.pop(timeout: 1)
    collect('k')

    expect(events.pop(timeout: 1)).to eq(['k', 1])
  end

  it 'does not deliver one value twice to a watcher added while an event is queued' do
    collect('k')
    hold = Thread::Queue.new
    watchers.add('busy', ->(_key, _value) { hold.pop(timeout: 1) })
    watchers.dispatch('busy', 0)
    watchers.dispatch('k', 2)
    collect('k')
    hold << :go

    expect(Array.new(2) { events.pop(timeout: 1) }).to eq([['k', 2], ['k', 2]])
    expect(events.pop(timeout: 0.1)).to be_nil
  end

  it 'sends UNWATCH once the last watcher of a key is removed' do
    first = collect('k')
    second = collect('k')
    first.unwatch
    second.unwatch
    second.unwatch

    expect(sent_so_far).to eq([watch_request('k'), unwatch_request('k')])
  end

  it 'never calls a removed watcher' do
    collect('k').unwatch
    watchers.dispatch('k', 1)

    expect(events.pop(timeout: 0.1)).to be_nil
  end

  it 'never calls a watcher removed while an event for it is queued' do
    hold = Thread::Queue.new
    watchers.add('k', ->(_key, _value) { hold.tap { events << :started }.pop(timeout: 1) })
    removed = collect('k')
    collect('k')
    watchers.dispatch('k', 1)
    events.pop(timeout: 1)
    removed.unwatch
    hold << :go

    expect(events.pop(timeout: 1)).to eq(['k', 1])
    expect(events.pop(timeout: 0.1)).to be_nil
  end

  it 'ignores a lost connection on unwatch' do
    watcher = collect('k')
    allow(connection).to receive(:notify).and_raise(Tarantool::ConnectionError, 'lost')

    expect { watcher.unwatch }.not_to raise_error
  end

  it 'ignores a write timeout on unwatch' do
    watcher = collect('k')
    allow(connection).to receive(:notify).and_raise(Tarantool::TimeoutError, 'socket write timed out')

    expect { watcher.unwatch }.not_to raise_error
  end

  it 'does not register a watcher whose WATCH failed' do
    allow(connection).to receive(:notify).and_raise(Tarantool::ClientClosedError, 'closed')

    expect { collect('k') }.to raise_error(Tarantool::ClientClosedError)
    watchers.dispatch('k', 1)
    expect(events.pop(timeout: 0.1)).to be_nil
  end

  it 'reports a failing callback and still notifies the others and acknowledges' do
    watchers.add('k', ->(_key, _value) { raise 'boom' })
    collect('k')
    sent.pop(timeout: 1)

    expect do
      watchers.dispatch('k', 1)
      events.pop(timeout: 1)
    end.to output(/tarantool watcher "k" failed: RuntimeError: boom/).to_stderr
    expect(sent.pop(timeout: 1)).to eq(watch_request('k'))
  end

  it 'keeps dispatching when an acknowledgement fails' do
    collect('k')
    allow(connection).to receive(:notify).and_raise(Tarantool::ClientClosedError, 'closed')
    watchers.dispatch('k', 1)
    watchers.dispatch('k', 2)

    expect(Array.new(2) { events.pop(timeout: 1) }).to eq([['k', 1], ['k', 2]])
  end

  it 'stops the dispatcher thread on close' do
    collect('k')
    watchers.close

    expect(Thread.list.none? { |thread| thread.name == 'tarantool-watchers' && thread.alive? }).to be(true)
  end

  it 'drops queued jobs on close instead of draining them' do
    hold = Thread::Queue.new
    collect_and_hold('k', 1, hold)
    watchers.dispatch('k', 1)
    events.pop(timeout: 1)
    watchers.dispatch('k', 2)
    closing = Thread.new { watchers.close }
    Thread.pass until closing.stop?
    hold << :go
    closing.join

    expect(events.pop(timeout: 0.1)).to be_nil
  end

  describe '#resubscribe' do
    let(:fresh) { instance_double(Tarantool::Client::Transport::Connection) }
    let(:resent) { [] }

    before { allow(fresh).to receive(:notify) { |request, **| resent << request } }

    it 'sends WATCH for every watched key over the given connection' do
      collect('a')
      collect('b')
      watchers.resubscribe(fresh)

      expect(resent).to eq([watch_request('a'), watch_request('b')])
    end

    it 'skips keys whose last watcher is gone' do
      collect('a').unwatch
      watchers.resubscribe(fresh)

      expect(resent).to be_empty
    end

    it 'sends WATCH for the other keys when one fails' do
      collect('a')
      collect('b')
      allow(fresh).to receive(:notify).with(watch_request('a'), any_args).and_raise(Tarantool::TimeoutError, 'slow')
      watchers.resubscribe(fresh)

      expect(resent).to eq([watch_request('b')])
    end

    it 'ignores a connection that is already gone' do
      collect('a')
      allow(fresh).to receive(:notify).and_raise(Tarantool::ConnectionError, 'lost')

      expect { watchers.resubscribe(fresh) }.not_to raise_error
    end
  end
end
