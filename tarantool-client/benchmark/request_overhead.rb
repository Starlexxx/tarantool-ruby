# frozen_string_literal: true

# Request path cost with and without instrumentation, against a running Tarantool:
#   bundle exec ruby -Ilib benchmark/request_overhead.rb [plain] [noop] [logger]
# TARANTOOL_URI overrides the shared container on 3301, ITERATIONS the number of requests per run.

require 'logger'
require 'tarantool/client'

# As cheap as an instrumenter gets.
class NoopInstrumenter
  def instrument(_name, _payload) = yield
end

ITERATIONS = Integer(ENV.fetch('ITERATIONS', 20_000))
VARIANTS = {
  'plain' => {},
  'noop' => { instrumenter: NoopInstrumenter.new },
  'logger' => { logger: Logger.new(File::NULL, level: :info) }
}.freeze
OPERATIONS = {
  'ping' => lambda(&:ping),
  'select' => ->(client) { client.select(:users, [1]) }
}.freeze

def run(client, operation)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  allocated = GC.stat(:total_allocated_objects)
  ITERATIONS.times { operation.call(client) }

  [ITERATIONS / (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started),
   (GC.stat(:total_allocated_objects) - allocated).fdiv(ITERATIONS)]
end

uri = ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301')
(ARGV.empty? ? VARIANTS.keys : ARGV).each do |variant|
  client = Tarantool::Client.new(uri, **VARIANTS.fetch(variant))
  OPERATIONS.each do |name, operation|
    run(client, operation)
    rate, allocations = run(client, operation)
    puts format('%-7<variant>s %-7<name>s %9<rate>.0f req/s %6<allocations>.1f objects/req',
                variant:, name:, rate:, allocations:)
  end
ensure
  client&.close
end
