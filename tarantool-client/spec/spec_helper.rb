# frozen_string_literal: true

require 'tarantool/client'

require_relative 'support/iproto_helpers'

RSpec.configure do |config|
  config.include IprotoHelpers
  config.disable_monkey_patching!
  config.order = :random
  config.filter_run_excluding :integration unless ENV['INTEGRATION']
end
