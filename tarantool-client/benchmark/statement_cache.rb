# frozen_string_literal: true

# Executes/s of one parameterised SELECT with and without the statement cache, against a running Tarantool:
#   bundle exec ruby -Ilib benchmark/statement_cache.rb
# TARANTOOL_URI overrides the shared container on 3301, ITERATIONS the number of executes per run.

require 'tarantool/client'

ITERATIONS = Integer(ENV.fetch('ITERATIONS', 20_000))
SQL = 'SELECT "id", "email" FROM "users" WHERE "id" = ?'
VARIANTS = { 'text' => {}, 'cached' => { statement_cache: 10 } }.freeze

def rate(client)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ITERATIONS.times { client.execute(SQL, [1]) }

  ITERATIONS / (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
end

uri = ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301')
VARIANTS.each do |variant, options|
  client = Tarantool::Client.new(uri, **options)
  rate(client)
  puts format('%-7<variant>s %9<rate>.0f executes/s', variant:, rate: rate(client))
ensure
  client&.close
end
