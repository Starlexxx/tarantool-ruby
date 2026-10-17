# frozen_string_literal: true

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
  end
end
