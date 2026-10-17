# frozen_string_literal: true

require 'rails'
require 'action_controller/railtie'
require 'tarantool/rails'

module Dummy
  # Minimal application booting the Railtie against spec/dummy/config.
  class Application < ::Rails::Application
    config.root = File.join(__dir__, 'dummy')
    config.eager_load = false
    config.logger = Logger.new(StringIO.new)
    config.log_level = :debug
    config.active_support.deprecation = :stderr
  end
end

Dummy::Application.initialize!

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  config.filter_run_excluding :integration unless ENV['INTEGRATION']
end
