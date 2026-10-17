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

      # The client fills the payload (request, space, index, ...) inside the block, once names are resolved, so the
      # name and attributes are set when the block is done. Finishing here rather than through Tracer#in_span records
      # an exception once, with its message as the status description.
      def instrument(name, payload, &block)
        span = @tracer.start_span(Attributes.name(name, payload), kind: :client)
        ::OpenTelemetry::Trace.with_span(span) { run(name, payload, &block) }
      rescue StandardError => e
        span&.record_exception(e)
        span&.status = ::OpenTelemetry::Trace::Status.error(e.message)
        raise
      ensure
        describe(span, name, payload) if span
        span&.finish
      end

      private

      def describe(span, name, payload)
        span.name = Attributes.name(name, payload)
        span.add_attributes(Attributes.for(name, payload, db_statement: @db_statement))
      end

      def run(name, payload, &)
        @instrumenter ? @instrumenter.instrument(name, payload, &) : yield
      end
    end
  end
end
