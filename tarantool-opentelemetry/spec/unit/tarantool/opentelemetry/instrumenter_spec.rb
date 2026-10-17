# frozen_string_literal: true

RSpec.describe Tarantool::OpenTelemetry::Instrumenter do
  subject(:instrumenter) { described_class.new }

  let(:spans) { EXPORTER.finished_spans }
  let(:span) { spans.first }
  let(:payload) { { request: :select, space: :users, index: :email, address: 'db1:3301' } }

  it 'opens one client span per request with the name and attributes of the event' do
    result = instrumenter.instrument('request.tarantool', payload) { :rows }

    expect(result).to eq(:rows)
    expect(span).to have_attributes(name: 'tarantool.select users', kind: :client)
    expect(span.attributes).to include('db.system' => 'tarantool', 'db.tarantool.index' => 'email',
                                       'server.port' => 3301)
  end

  it 'names and describes the span from what the block put into the payload' do
    late = { address: 'db1:3301' }
    instrumenter.instrument('request.tarantool', late) { late.merge!(request: :update, space: 'users', index: 0) }

    expect(span.name).to eq('tarantool.update users')
    expect(span.attributes).to include('db.operation' => 'update', 'db.tarantool.index' => 0)
  end

  it 'uses the tarantool-client tracer by default' do
    instrumenter.instrument('request.tarantool', payload) { nil }

    expect(span.instrumentation_scope).to have_attributes(name: 'tarantool-client', version: Tarantool::Client::VERSION)
  end

  it 'takes a tracer of its own' do
    tracer = OpenTelemetry.tracer_provider.tracer('my-app', '2.0')
    described_class.new(tracer:).instrument('fork.tarantool', {}) { nil }

    expect(span.instrumentation_scope).to have_attributes(name: 'my-app', version: '2.0')
  end

  it 'opens a span for a lifecycle event' do
    instrumenter.instrument('shutdown.tarantool', { address: 'db1:3301', pending: 2 }) { nil }

    expect(span).to have_attributes(name: 'tarantool.shutdown', kind: :client)
    expect(span.attributes).to include('tarantool.pending' => 2)
  end

  it 'records a raised exception once, sets the error status and re-raises' do
    error = Tarantool::ServerError.new('Duplicate key', code: 3)

    expect { instrumenter.instrument('request.tarantool', payload) { raise error } }.to raise_error(error)
    expect(span.events.map(&:name)).to eq(['exception'])
    expect(span.status).to have_attributes(code: OpenTelemetry::Trace::Status::ERROR, description: 'Duplicate key')
  end

  it 'marks a finished span ok only implicitly' do
    instrumenter.instrument('request.tarantool', payload) { nil }

    expect(span.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
  end

  describe 'db_statement' do
    let(:payload) { { request: :execute, sql: 'SELECT 1', address: 'db1:3301' } }

    it 'omits the SQL text by default' do
      instrumenter.instrument('request.tarantool', payload) { nil }

      expect(span.attributes).not_to have_key('db.statement')
    end

    it 'includes it when asked' do
      described_class.new(db_statement: :include).instrument('request.tarantool', payload) { nil }

      expect(span.attributes).to include('db.statement' => 'SELECT 1')
    end

    it 'rejects any other value' do
      expect { described_class.new(db_statement: :obfuscate) }
        .to raise_error(ArgumentError, 'db_statement must be :omit or :include, got :obfuscate')
    end
  end

  describe 'chaining' do
    let(:chained) { Chained.new }

    before do
      stub_const('Chained', Class.new do
        attr_reader :calls

        def instrument(name, payload)
          (@calls ||= []) << [name, payload, OpenTelemetry::Trace.current_span.name]

          yield
        end
      end)
    end

    it 'calls the chained instrumenter inside the span with the same payload and block' do
      result = described_class.new(instrumenter: chained).instrument('request.tarantool', payload) { :rows }

      expect(result).to eq(:rows)
      expect(chained.calls).to eq([['request.tarantool', payload, 'tarantool.select users']])
      expect(chained.calls.first.fetch(1)).to be(payload)
    end
  end

  it 'works with the API alone when no SDK is configured' do
    tracer = OpenTelemetry::Trace::Tracer.new

    expect(described_class.new(tracer:).instrument('request.tarantool', payload) { :rows }).to eq(:rows)
  end
end
