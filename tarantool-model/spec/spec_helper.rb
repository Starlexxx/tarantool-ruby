# frozen_string_literal: true

require 'tarantool/model'
require 'tarantool/crud'

Dir[File.join(__dir__, 'support', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  config.filter_run_excluding :integration unless ENV['INTEGRATION']
  config.filter_run_excluding :crud unless ENV['TARANTOOL_MODEL_CRUD_URI']
end
