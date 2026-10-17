# frozen_string_literal: true

require 'opentelemetry'
require 'tarantool/client'

require_relative 'opentelemetry/version'
require_relative 'opentelemetry/attributes'

module Tarantool
  # OpenTelemetry spans for the events a Tarantool::Client emits through its instrumenter.
  module OpenTelemetry
  end
end
