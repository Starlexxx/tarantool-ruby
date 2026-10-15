# frozen_string_literal: true

RSpec.describe Tarantool::Client::Transport::TimedLock do
  subject(:lock) { described_class.new }

  def deadline(timeout) = Tarantool::Client::Transport::Deadline.after(timeout)

  def while_held
    held = Thread::Queue.new
    release = Thread::Queue.new
    holder = Thread.new { lock.synchronize(nil) { held.push(true) && release.pop } }
    held.pop
    yield
  ensure
    release << true
    holder.join
  end

  it 'returns the block value' do
    expect(lock.synchronize(deadline(1)) { :done }).to eq(:done)
  end

  it 'raises TimeoutError when the lock stays held past the deadline' do
    while_held do
      expect { lock.synchronize(deadline(0.05)) { :never } }.to raise_error(Tarantool::TimeoutError)
    end
  end

  it 'lets a waiter in once the holder leaves' do
    waiter = nil
    while_held { waiter = Thread.new { lock.synchronize(deadline(1)) { :acquired } } }

    expect(waiter.value).to eq(:acquired)
  end

  it 'releases the lock when the block raises' do
    expect { lock.synchronize(nil) { raise 'boom' } }.to raise_error(RuntimeError, 'boom')
    expect(lock.synchronize(deadline(0.05)) { :free }).to eq(:free)
  end

  it 'stays usable after a waiting thread is killed' do
    while_held do
      waiter = Thread.new { lock.synchronize(nil) { :never } }
      sleep 0.05
      waiter.kill.join
    end

    expect(lock.synchronize(deadline(0.1)) { :free }).to eq(:free)
  end
end
