# frozen_string_literal: true

# Request latency and throughput against a running Tarantool: select by primary key and insert on one
# connection, select over a Pool from 8 threads. Creates and drops the space bench_items.
#   bundle exec ruby -Ilib benchmark/latency.rb
# TARANTOOL_URI overrides the shared container on 3301, ITERATIONS the number of requests per case.

require 'tarantool/client'
require_relative 'measure'

ITERATIONS = Integer(ENV.fetch('ITERATIONS', 20_000))
ROWS = 10_000
THREADS = 8
ADDRESS = ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301')

CREATE = <<~LUA
  local space = box.schema.space.create('bench_items', {if_not_exists = true, format = {
    {name = 'id', type = 'unsigned'}, {name = 'name', type = 'string'},
    {name = 'value', type = 'double'}, {name = 'tags', type = 'array'}}})
  space:create_index('primary', {parts = {'id'}, if_not_exists = true})
LUA
DROP = 'if box.space.bench_items then box.space.bench_items:drop() end'

def tuple(id) = [id, "item #{id}", id * 0.5, %w[a b c]]

def fill(client)
  (1..ROWS).each { |id| client.replace(:bench_items, tuple(id)) }
end

client = Tarantool::Client.new(ADDRESS)
pool = Tarantool::Client::Pool.new([ADDRESS])
begin
  client.eval(CREATE)
  fill(client)
  Measure.environment(client_version: "tarantool-client #{Tarantool::Client::VERSION}",
                      server_version: client.server_version, uri: ADDRESS)

  Measure.report('select by pk', ITERATIONS) { |index| client.select(:bench_items, [(index % ROWS) + 1]) }
  next_id = 100_000
  Measure.report('insert', ITERATIONS) { client.insert(:bench_items, tuple(next_id += 1)) }
  client.eval('local last = ... for id = 100000, last do box.space.bench_items:delete(id) end', [next_id])
  Measure.report('select by pk, pool x8', ITERATIONS, threads: THREADS) do |index|
    pool.select(:bench_items, [(index % ROWS) + 1])
  end
ensure
  client.eval(DROP)
  pool.close
  client.close
end
