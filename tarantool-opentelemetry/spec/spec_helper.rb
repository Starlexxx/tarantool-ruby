# frozen_string_literal: true

require 'opentelemetry/sdk'
require 'tarantool/opentelemetry'

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new

OpenTelemetry::SDK.configure do |config|
  config.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER))
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  config.filter_run_excluding :integration unless ENV['INTEGRATION']
  config.before { EXPORTER.reset }
end
