# frozen_string_literal: true

RSpec.describe Tarantool::Rails::LogSubscriber do
  subject(:subscriber) { described_class.new }

  let(:io) { StringIO.new }
  let(:formatter) { ->(severity, _time, _progname, message) { "#{severity} #{message}\n" } }
  let(:logger) { Logger.new(io, level: :debug, formatter:) }

  before do
    ActiveSupport::LogSubscriber.logger = logger
    ActiveSupport::LogSubscriber.colorize_logging = false
    described_class.reset_runtime
  end

  after do
    ActiveSupport::LogSubscriber.logger = nil
    ActiveSupport::LogSubscriber.colorize_logging = true
  end

  def emit(name, payload, duration: 0.42)
    started = Time.now
    finished = started + (duration / 1000.0)
    event = ActiveSupport::Notifications::Event.new("#{name}.tarantool", started, finished, '1', payload)
    subscriber.public_send(name, event)

    io.string
  end

  def request(payload, **)
    emit(:request, { address: 'db1:3301' }.merge(payload), **)
  end

  describe '#request' do
    it 'names the request, space and secondary index' do
      line = request({ request: :select, space: :users, index: :email })

      expect(line).to eq("DEBUG Tarantool select users by email (0.42ms) db1:3301\n")
    end

    it 'leaves the primary index out' do
      request({ request: :select, space: :users, index: 0 })
      request({ request: :delete, space: 'users', index: 'primary' })

      expect(io.string).to eq("DEBUG Tarantool select users (0.42ms) db1:3301\n" \
                              "DEBUG Tarantool delete users (0.42ms) db1:3301\n")
    end

    it 'names the function of a call' do
      line = request({ request: :call, function: 'user.touch' })

      expect(line).to eq("DEBUG Tarantool call user.touch (0.42ms) db1:3301\n")
    end

    it 'shows the SQL text or the prepared statement id' do
      request({ request: :execute, sql: 'SELECT 1' })
      request({ request: :execute, statement_id: 4 })

      expect(io.string).to eq("DEBUG Tarantool execute (0.42ms) SELECT 1 db1:3301\n" \
                              "DEBUG Tarantool execute #4 (0.42ms) db1:3301\n")
    end

    it 'appends the error class and code, never the message' do
      error = Tarantool::ServerError.new('Duplicate key exists in unique index', code: 3)
      line = request({ request: :insert, space: :users, exception: [error.class.name, error.message],
                       exception_object: error })

      expect(line).to eq("DEBUG Tarantool insert users (0.42ms) db1:3301 Tarantool::ServerError(3)\n")
    end

    it 'appends the error class alone when the error has no code' do
      line = request({ request: :insert, space: :users, exception: ['Tarantool::TimeoutError', 'timed out'] })

      expect(line).to eq("DEBUG Tarantool insert users (0.42ms) db1:3301 Tarantool::TimeoutError\n")
    end

    it 'copes with a request that was never built and notes a schema reload' do
      expect(request({ schema_reloaded: true })).to eq("DEBUG Tarantool (0.42ms) db1:3301 schema_reloaded\n")
    end

    it 'logs nothing above debug but still counts the time' do
      logger.level = :info

      expect([request({ request: :select, space: :users }), described_class.runtime.round(2)]).to eq(['', 0.42])
    end

    it 'colors the name when colorize_logging is on' do
      ActiveSupport::LogSubscriber.colorize_logging = true

      line = request({ request: :select, space: :users })

      expect(line).to start_with("DEBUG \e[1m\e[35mTarantool select users\e[0m (0.42ms)")
    end
  end

  describe 'lifecycle events' do
    it 'warns on disconnect' do
      line = emit(:disconnect, { address: 'db1:3301', reason: 'EOF' })

      expect(line).to eq("WARN Tarantool disconnected from db1:3301: EOF\n")
    end

    it 'reports a reconnect' do
      line = emit(:reconnect, { address: 'db1:3301', attempts: 3 })

      expect(line).to eq("INFO Tarantool reconnected to db1:3301 after 3 attempts\n")
    end

    it 'reports a failed reconnect as an error' do
      line = emit(:reconnect_failed, { address: 'db1:3301', exception: ['Tarantool::ConnectionError', 'refused'] })

      expect(line).to eq("ERROR Tarantool gave up reconnecting to db1:3301: Tarantool::ConnectionError: refused\n")
    end

    it 'reports a reopen after fork' do
      expect(emit(:fork, { address: 'db1:3301' })).to eq("INFO Tarantool reopened db1:3301 after fork\n")
    end

    it 'reports a role change' do
      emit(:role_change, { address: 'db1:3301', read_only: true })
      emit(:role_change, { address: 'db1:3301', read_only: false })

      expect(io.string).to eq("INFO Tarantool db1:3301 is now read-only\nINFO Tarantool db1:3301 is now writable\n")
    end
  end

  describe '.runtime' do
    it 'accumulates request durations and reset returns them' do
      request({ request: :select }, duration: 1.5)
      request({ request: :select }, duration: 2.0)

      expect([described_class.reset_runtime.round(2), described_class.runtime]).to eq([3.5, 0.0])
    end
  end
end
