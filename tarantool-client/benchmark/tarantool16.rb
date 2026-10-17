# frozen_string_literal: true

# The select and insert cases of latency.rb through the tarantool16 gem (the other Ruby connector that speaks
# IPROTO 1.6+), for comparison. The gem is not a dependency: `gem install tarantool16` first. Creates and drops
# bench_items like latency.rb; a gem that cannot connect or fails is reported, not fatal.
#   bundle exec ruby -Ilib benchmark/tarantool16.rb
# TARANTOOL_URI overrides the shared container on 3301, ITERATIONS the number of requests per case.

require 'uri'
require_relative 'measure'

begin
  require 'tarantool16'
rescue LoadError => e
  puts "tarantool16 is not installed (#{e.message}); gem install tarantool16"
  exit 0
end

ITERATIONS = Integer(ENV.fetch('ITERATIONS', 20_000))
ROWS = 10_000
URI_STRING = ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301')

CREATE = <<~LUA
  local space = box.schema.space.create('bench_items', {if_not_exists = true, format = {
    {name = 'id', type = 'unsigned'}, {name = 'name', type = 'string'},
    {name = 'value', type = 'double'}, {name = 'tags', type = 'array'}}})
  space:create_index('primary', {parts = {'id'}, if_not_exists = true})
LUA
DROP = 'if box.space.bench_items then box.space.bench_items:drop() end'

def tuple(id) = [id, "item #{id}", id * 0.5, %w[a b c]]

# The gem connects to the first address of the name, ::1 for localhost, which the container does not listen on.
uri = URI.parse(URI_STRING)
host = uri.host == 'localhost' ? '127.0.0.1' : uri.host
db = nil
begin
  db = Tarantool16.new(host: "#{host}:#{uri.port}", user: uri.user, password: uri.password)
  db.eval(CREATE, [])
  (1..ROWS).each { |id| db.replace(:bench_items, tuple(id)) }
  Measure.environment(client_version: "tarantool16 #{Tarantool16::VERSION}", server_version: 'see latency.rb',
                      uri: URI_STRING)
  Measure.report('select by pk', ITERATIONS) { |index| db.select(:bench_items, [(index % ROWS) + 1]) }
  next_id = 200_000
  Measure.report('insert', ITERATIONS) { db.insert(:bench_items, tuple(next_id += 1)) }
  db.eval('local last = ... for id = 200000, last do box.space.bench_items:delete(id) end', [next_id])
rescue StandardError => e
  puts "tarantool16 failed: #{e.class}: #{e.message}"
ensure
  db&.eval(DROP, [])
end
