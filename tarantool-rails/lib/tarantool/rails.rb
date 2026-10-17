# frozen_string_literal: true

require 'monitor'
require 'tarantool/client'
require 'tarantool/model'
require 'tarantool/schema'

require_relative 'rails/version'
require_relative 'rails/errors'
require_relative 'rails/configuration'

module Tarantool
  # Rails integration: configuration from config/tarantool.yml, one Pool per process, models on it, log lines,
  # schema rake tasks and generators.
  module Rails
    LOCK = Monitor.new
    private_constant :LOCK

    class << self
      attr_accessor :config, :schema_path
      attr_writer :schema

      def pool
        LOCK.synchronize { @pool ||= build_pool }
      end

      def storage
        LOCK.synchronize { @storage ||= build_storage }
      end

      def schema
        LOCK.synchronize { @schema ||= load_schema }
      end

      def admin_client
        uri = configured.admin_uri
        raise Error, 'admin_uri is not set in config/tarantool.yml' unless uri

        client = Tarantool::Client.new(uri)

        yield client
      ensure
        client&.close
      end

      def disconnect!
        LOCK.synchronize do
          @pool&.close
          @pool = nil
          @storage = nil
        end
      end

      private

      def configured
        config || raise(Error, 'Tarantool::Rails.config is not set; is the Railtie loaded?')
      end

      def build_pool
        Tarantool::Client::Pool.new(configured.addresses, **configured.client_options,
                                                          instrumenter: ActiveSupport::Notifications)
      end

      def build_storage
        configured.storage == :box ? build_box_storage : build_crud_storage
      end

      def build_box_storage
        Model::Storage::Box.new(pool, read: configured.read, write: configured.write)
      end

      def build_crud_storage
        require 'tarantool/crud'
        options = configured.crud
        crud = Tarantool::Crud::Client.new(pool, **options.slice(:read, :write, :timeout_margin))

        Model::Storage::Crud.new(crud, primary_index: options[:primary_index])
      rescue LoadError
        raise Error, 'storage: crud needs the tarantool-crud gem; add it to the Gemfile'
      end

      def load_schema
        path = schema_path.to_s
        load(path)

        @schema || raise(Error, "#{path} must assign Tarantool::Rails.schema")
      end
    end
  end
end
