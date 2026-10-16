# frozen_string_literal: true

RSpec.describe Tarantool::Client::Instrumentation do
  let(:instrumenter) { RecordingInstrumenter.new }
  let(:log) { StringIO.new }
  let(:server) { status_server('a', { 'a' => true }) }
  let(:pool) do
    Tarantool::Client::Pool.new(
      [server.uri], user: 'app', password: 'secret', instrumenter:, logger: Logger.new(log, level: :debug),
                    reconnect_delay: 0.01, reconnect_max_delay: 0.02, reconnect_attempts: 1
    )
  end

  after do
    pool.close
    server.stop
  end

  def drive_requests
    pool.eval('return 1')
    expect { pool.select(:missing, 1) }.to raise_error(Tarantool::SchemaError)
  end

  def drive_reconnects
    server.disconnect
    wait_for { instrumenter.payloads('reconnect.tarantool').any? }
    server.refusing = true
    server.disconnect
    wait_for { instrumenter.payloads('reconnect_failed.tarantool').any? }
  end

  it 'keeps the password out of every payload and log line' do
    drive_requests
    drive_reconnects
    pool.close

    expect(instrumenter.events.map(&:first).uniq).to include(
      'request.tarantool', 'role_change.tarantool', 'disconnect.tarantool', 'reconnect.tarantool',
      'reconnect_failed.tarantool'
    )
    expect(instrumenter.events.inspect).not_to include('secret')
    expect(log.string).not_to include('secret')
  end
end
