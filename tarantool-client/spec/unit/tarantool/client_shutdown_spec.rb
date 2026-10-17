# frozen_string_literal: true

# The server announces its shutdown through box.shutdown and waits for subscribed connections to close.
RSpec.describe Tarantool::Client do
  let(:instrumenter) { RecordingInstrumenter.new }
  let(:options) { {} }
  let(:queues) { { holds: Thread::Queue.new, watch_keys: Thread::Queue.new } }
  let(:server) do
    FakeTarantool.new do |request, fake|
      case request.type
      when 0x4a then queues[:watch_keys] << request.body[0x57]
      when 0x0a then Thread.new { fake.reply(request, [queues[:holds].pop]) }
      else fake.reply(request, [])
      end
    end
  end
  let(:client) { described_class.new(server.uri, reconnect_delay: 0.01, request_timeout: 1, instrumenter:, **options) }

  after do
    client.close
    server.stop
  end

  def shutdown_announced
    client
    server.event('box.shutdown', true)
  end

  def in_flight_call = Thread.new { client.call('slow') }

  it 'subscribes to box.shutdown on connect' do
    client

    expect(queues[:watch_keys].pop(timeout: 1)).to eq('box.shutdown')
  end

  it 'ignores the value sent on subscribing before a shutdown starts' do
    client
    server.event('box.shutdown')
    sleep 0.05

    expect([client.connected?, instrumenter.payloads('shutdown.tarantool')]).to eq([true, []])
  end

  it 'stops being connected and reports the shutdown with the requests in flight' do
    call = in_flight_call
    sleep 0.05
    shutdown_announced
    wait_for { instrumenter.payloads('shutdown.tarantool').any? }

    expect([client.connected?, instrumenter.payloads('shutdown.tarantool')])
      .to eq([false, [{ address: server.path, pending: 1 }]])
    queues[:holds] << 1
    call.join
  end

  it 'lets requests in flight finish before closing the connection' do
    call = in_flight_call
    sleep 0.05
    shutdown_announced
    wait_for { instrumenter.payloads('shutdown.tarantool').any? }
    queues[:holds] << 42

    expect(call.value).to eq([42])
    wait_for { instrumenter.payloads('disconnect.tarantool').any? }
    expect(instrumenter.payloads('disconnect.tarantool').first[:reason]).to eq("server #{server.path} is shutting down")
  end

  it 'reconnects afterwards and serves requests again' do
    shutdown_announced
    wait_for { server.connections == 2 }

    expect(client.ping).to be(true)
  end

  it 'closes the connection at the request timeout, after the requests in flight timed out' do
    call = in_flight_call
    sleep 0.05
    shutdown_announced

    expect { call.value }.to raise_error(Tarantool::TimeoutError)
    wait_for { instrumenter.payloads('disconnect.tarantool').any? }
    expect(instrumenter.payloads('disconnect.tarantool').first[:reason]).to include('is shutting down')
  end

  it 'closes at once when the client is closed while draining' do
    in_flight_call
    sleep 0.05
    shutdown_announced
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    client.close

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.5
  end

  it 'delivers the event to a watcher of box.shutdown as well' do
    events = Thread::Queue.new
    client.watch('box.shutdown') { |_key, value| events << value }
    events.pop(timeout: 1)
    server.event('box.shutdown', true)

    expect(events.pop(timeout: 1)).to be(true)
  end

  context 'without reconnect' do
    let(:options) { { reconnect: false } }

    it 'fails later requests with the shutdown reason' do
      shutdown_announced
      wait_for { instrumenter.payloads('disconnect.tarantool').any? }

      expect { client.ping }.to raise_error(Tarantool::ConnectionError, /is shutting down/)
    end
  end
end
