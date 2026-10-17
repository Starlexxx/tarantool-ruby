# frozen_string_literal: true

require 'rails/generators'

module Tarantool
  module Generators
    # rails g tarantool:install
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      def create_configuration
        copy_file 'tarantool.yml', 'config/tarantool.yml'
      end

      def create_schema
        copy_file 'tarantool_schema.rb', 'config/tarantool_schema.rb'
      end
    end
  end
end
