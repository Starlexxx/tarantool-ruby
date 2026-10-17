# frozen_string_literal: true

module Tarantool
  module OpenTelemetry
    # An instrumenter for Tarantool::Client and Pool: one client span per event, the block run inside it. Another
    # instrumenter (ActiveSupport::Notifications, a logger wrapper) can be chained; it runs inside the span too.
    class Instrumenter
      DB_STATEMENT = %i[omit include].freeze
      private_constant :DB_STATEMENT

      def initialize(instrumenter: nil, tracer: nil, db_statement: :omit)
        unless DB_STATEMENT.include?(db_statement)
          raise ArgumentError, "db_statement must be :omit or :include, got #{db_statement.inspect}"
        end

        @instrumenter = instrumenter
        @tracer = tracer || ::OpenTelemetry.tracer_provider.tracer('tarantool-client', Tarantool::Client::VERSION)
        @db_statement = db_statement
      end

      # The span is finished here rather than by Tracer#in_span so an exception is recorded once, with its message
      # as the status description.
      def instrument(name, payload, &block)
        attributes = Attributes.for(name, payload, db_statement: @db_statement)
        span = @tracer.start_span(Attributes.name(name, payload), kind: :client, attributes:)
        ::OpenTelemetry::Trace.with_span(span) { run(name, payload, &block) }
      rescue StandardError => e
        span&.record_exception(e)
        span&.status = ::OpenTelemetry::Trace::Status.error(e.message)
        raise
      ensure
        span&.finish
      end

      private

      def run(name, payload, &)
        @instrumenter ? @instrumenter.instrument(name, payload, &) : yield
      end
    end
  end
end
