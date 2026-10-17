# frozen_string_literal: true

module Tarantool
  module Rails
    # Wires configuration, the default model storage, logging and rake tasks into the application.
    class Railtie < ::Rails::Railtie
      config.tarantool = ActiveSupport::OrderedOptions.new
      config.tarantool.log = true

      # A missing config/tarantool.yml is not an error at boot: the install generator has to be able to run.
      initializer 'tarantool.configuration' do |app|
        Tarantool::Rails.schema_path = app.config.tarantool.schema_path || app.root.join('config/tarantool_schema.rb')
        next unless app.root.join('config/tarantool.yml').exist?

        section = app.config_for(:tarantool)
        raise Error, "config/tarantool.yml has no #{::Rails.env} section" unless section

        Tarantool::Rails.config = Configuration.from_hash(section)
      end

      initializer 'tarantool.model' do
        Tarantool::Rails.use_default_storage!
      end

      initializer 'tarantool.log' do |app|
        next unless app.config.tarantool.log

        LogSubscriber.attach_to :tarantool
        ActiveSupport.on_load(:action_controller) { include ControllerRuntime }
      end

      rake_tasks { load File.expand_path('tasks/schema.rake', __dir__) }
    end
  end
end
