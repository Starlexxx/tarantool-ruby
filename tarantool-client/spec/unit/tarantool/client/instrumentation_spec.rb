# frozen_string_literal: true

RSpec.describe Tarantool::Client::Instrumentation do
  subject(:instrumentation) { described_class.build(config) }

  let(:instrumenter) { RecordingInstrumenter.new }
  let(:config) { Tarantool::Client::Configuration.build('db.local:3301', instrumenter:) }

  def build_with(instrumenter) = described_class.build(Tarantool::Client::Configuration.build(instrumenter:))

  describe '.build' do
    it 'returns nil without an instrumenter or a logger' do
      expect(described_class.build(Tarantool::Client::Configuration.build)).to be_nil
    end

    it 'builds with a logger alone' do
      config = Tarantool::Client::Configuration.build(logger: Logger.new(StringIO.new))

      expect(described_class.build(config)).to be_a(described_class)
    end
  end

  describe '#request' do
    let(:notifications) do
      Class.new do
        attr_reader :payload

        def instrument(_name, payload)
          @payload = payload
          yield
        rescue StandardError => e
          payload[:exception] = [e.class.name, e.message]
          payload[:exception_object] = e
          raise
        end
      end.new
    end

    it 'emits request.tarantool with the address and returns the block value' do
      expect(instrumentation.request({ request: :ping }) { :pong }).to eq(:pong)
      expect(instrumenter.events).to eq([['request.tarantool', { request: :ping, address: 'db.local:3301' }]])
    end

    it 'returns the block value whatever the instrumenter returns' do
      ignoring = Class.new do
        def instrument(*)
          yield
          nil
        end
      end.new

      expect(build_with(ignoring).request({}) { :pong }).to eq(:pong)
    end

    it 'adds the ActiveSupport exception keys and re-raises' do
      error = Tarantool::ConnectionError.new('down')

      expect { instrumentation.request({ request: :ping }) { raise error } }.to raise_error(error)
      expect(instrumenter.payloads('request.tarantool').first)
        .to include(exception: ['Tarantool::ConnectionError', 'down'], exception_object: error)
    end

    it 'keeps one payload shape when the instrumenter writes the exception keys itself' do
      expect { build_with(notifications).request({ request: :ping }) { raise 'boom' } }.to raise_error('boom')
      expect(notifications.payload.keys).to eq(%i[request address exception exception_object])
    end
  end

  describe '#notify' do
    it 'emits the event with the address' do
      instrumentation.notify('fork.tarantool')

      expect(instrumenter.events).to eq([['fork.tarantool', { address: 'db.local:3301' }]])
    end

    it 'reports a failing instrumenter instead of raising' do
      failing = Class.new { def instrument(*) = raise('broken') }.new

      expect { build_with(failing).notify('fork.tarantool') }
        .to output(/fork.tarantool instrumentation failed: RuntimeError: broken/).to_stderr
    end
  end
end
