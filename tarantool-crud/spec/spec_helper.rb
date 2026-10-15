# frozen_string_literal: true

require 'tarantool/crud'

require_relative 'support/fake_caller'
require_relative 'support/crud_responses'

RSpec.configure do |config|
  config.include CrudResponses
  config.disable_monkey_patching!
  config.order = :random
  config.filter_run_excluding :integration unless ENV['INTEGRATION']
end
