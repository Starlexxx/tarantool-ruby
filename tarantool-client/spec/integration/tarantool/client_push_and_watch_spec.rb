# frozen_string_literal: true

require 'securerandom'

RSpec.describe Tarantool::Client, :integration do
  subject(:client) { described_class.new(uri) }

  let(:uri) { ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301') }
  let(:key) { "watch_#{SecureRandom.hex(8)}" }
  let(:events) { Thread::Queue.new }

  after { client.close }

  def broadcast(value) = client.eval('box.broadcast(...)', [key, value])

  it 'passes box.session.push messages to on_push' do
    messages = []
    result = client.call('box.session.push', [{ 'step' => 1 }], on_push: ->(message) { messages << message })

    expect(result).to eq([true])
    expect(messages).to eq([{ 'step' => 1 }])
  end

  it 'delivers the current value and then each broadcast' do
    client.watch(key) { |*event| events << event }

    expect(events.pop(timeout: 1)).to eq([key, nil])
    broadcast({ 'n' => 1 })
    expect(events.pop(timeout: 1)).to eq([key, { 'n' => 1 }])
  end

  it 'gives a second watcher of the same key the latest value' do
    broadcast(1)
    client.watch(key) { |*event| events << event }
    events.pop(timeout: 1)
    client.watch(key) { |*event| events << event }

    expect(events.pop(timeout: 1)).to eq([key, 1])
  end

  it 'stops delivering after unwatch but keeps delivering to other watchers' do
    removed = client.watch(key) { |*event| events << event }
    client.watch(key) { |_key, value| events << [:kept, value] }
    events.pop(timeout: 1)
    events.pop(timeout: 1)
    removed.unwatch
    broadcast(2)

    expect(events.pop(timeout: 1)).to eq([:kept, 2])
    expect(events.pop(timeout: 0.2)).to be_nil
  end

  it 'reports the instance state through box.status' do
    client.watch('box.status') { |_key, value| events << value }

    expect(events.pop(timeout: 1)).to include('is_ro' => false, 'status' => 'running')
  end
end
