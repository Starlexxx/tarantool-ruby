# frozen_string_literal: true

require 'tarantool/model'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  config.filter_run_excluding :integration unless ENV['INTEGRATION']
end
