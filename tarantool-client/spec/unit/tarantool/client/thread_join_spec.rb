# frozen_string_literal: true

RSpec.describe Tarantool::Client::ThreadJoin do
  def dead_thread(error)
    thread = Thread.new { raise error }
    thread.report_on_exception = false
    sleep 0.01 while thread.alive?
    thread
  end

  it 'joins a thread that died with an exception without raising it' do
    expect(described_class.join(dead_thread(NoMemoryError.new('gone')))).to be_nil
  end

  it 'does nothing for no thread or the current one' do
    expect([described_class.join(nil), described_class.join(Thread.current)]).to eq([nil, nil])
  end

  it 'lets an exception raised in the waiting thread through' do
    sleeper = Thread.new { sleep }
    waiter = Thread.new { described_class.join(sleeper) }.tap { |thread| thread.report_on_exception = false }
    sleep 0.01 until waiter.status == 'sleep'
    waiter.raise(Interrupt)

    expect { waiter.join }.to raise_error(Interrupt)
  ensure
    sleeper.kill.join
  end
end
