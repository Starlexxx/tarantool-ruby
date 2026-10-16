# frozen_string_literal: true

require 'tarantool/client'
require 'logger'
require 'stringio'

require_relative 'support/iproto_helpers'
require_relative 'support/wait_helpers'
require_relative 'support/fake_tarantool'
require_relative 'support/dripping_tarantool'
require_relative 'support/pool_helpers'
require_relative 'support/fork_fake_tarantool'
require_relative 'support/recording_instrumenter'

RSpec.configure do |config|
  config.include IprotoHelpers
  config.include WaitHelpers
  config.include PoolHelpers
  config.disable_monkey_patching!
  config.order = :random
  config.filter_run_excluding :integration unless ENV['INTEGRATION']
  config.filter_run_excluding :failover unless ENV['TARANTOOL_FAILOVER_URIS']
end
