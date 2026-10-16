# frozen_string_literal: true

RSpec.describe Tarantool::Client::Instrumentation::LogInstrumenter do
  subject(:instrumenter) { described_class.new(logger, nil) }

  let(:output) { StringIO.new }
  let(:logger) { Logger.new(output, level: :debug) }

  def notify(name, payload) = instrumenter.instrument(name, { address: 'db:3301', **payload }) { nil }

  it 'logs a request at debug with its fields and duration and returns the block value' do
    payload = { request: :select, space: :users, index: :email, address: 'db:3301' }

    expect(instrumenter.instrument('request.tarantool', payload) { :rows }).to eq(:rows)
    expect(output.string).to match(/DEBUG -- : tarantool select space=users index=email \d+\.\d{2}ms db:3301$/)
  end

  it 'logs the exception and the schema reload of a failed request' do
    payload = { request: :call, function: 'f', address: 'db:3301', schema_reloaded: true }
    failing = lambda do
      payload[:exception] = %w[RuntimeError boom]
      raise 'boom'
    end

    expect { instrumenter.instrument('request.tarantool', payload, &failing) }.to raise_error('boom')
    expect(output.string).to match(/tarantool call function=f \S+ms db:3301 error=RuntimeError: boom schema_reloaded$/)
  end

  it 'builds no request line when the logger is above debug' do
    logger.level = :info
    allow(Tarantool::Client::Instrumentation::LogLines).to receive(:line).and_call_original
    instrumenter.instrument('request.tarantool', { request: :ping, address: 'db:3301' }) { nil }

    expect(Tarantool::Client::Instrumentation::LogLines).not_to have_received(:line)
  end

  it 'runs the block inside the wrapped instrumenter' do
    inner = RecordingInstrumenter.new
    described_class.new(logger, inner).instrument('fork.tarantool', { address: 'db:3301' }) { nil }

    expect(inner.events).to eq([['fork.tarantool', { address: 'db:3301' }]])
    expect(output.string).to include('INFO -- : tarantool reopened connection to db:3301 after fork')
  end

  it 'logs connection loss as a warning and a reconnect as info' do
    notify('disconnect.tarantool', reason: 'reset')
    notify('reconnect.tarantool', attempts: 1)

    expect(output.string).to include('WARN -- : tarantool disconnected from db:3301: reset')
    expect(output.string).to include('INFO -- : tarantool reconnected to db:3301 after 1 attempt')
  end

  it 'logs giving up as an error and role changes as info' do
    notify('reconnect_failed.tarantool', exception: ['Tarantool::ConnectionError', 'refused'])
    notify('role_change.tarantool', read_only: false)

    expect(output.string)
      .to include('ERROR -- : tarantool gave up reconnecting to db:3301: Tarantool::ConnectionError: refused')
    expect(output.string).to include('INFO -- : tarantool db:3301 is now writable')
  end

  it 'ignores events it does not know' do
    notify('other.tarantool', {})

    expect(output.string).to be_empty
  end
end
