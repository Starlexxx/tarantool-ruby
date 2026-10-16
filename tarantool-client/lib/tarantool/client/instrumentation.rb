# frozen_string_literal: true

module Tarantool
  class Client
    # Emits request and lifecycle events to the configured instrumenter, with the logger wrapped around it.
    # Exception keys follow ActiveSupport::Notifications, which writes the same values again, so a payload looks
    # the same whatever the instrumenter.
    # @api private
    class Instrumentation
      REQUEST = 'request.tarantool'

      def self.build(config)
        instrumenter = config.instrumenter
        instrumenter = LogInstrumenter.new(config.logger, instrumenter) if config.logger

        new(instrumenter, config) if instrumenter
      end

      def self.exception_keys(exception)
        { exception: [exception.class.name, exception.message], exception_object: exception }
      end

      def initialize(instrumenter, config)
        @instrumenter = instrumenter
        @address = config.address
        @logger = config.logger
      end

      # The block's value is kept here: a duck-typed instrumenter need not return it.
      def request(payload)
        payload[:address] = @address
        result = nil
        @instrumenter.instrument(REQUEST, payload) do
          result = yield
        rescue Exception => e
          payload.merge!(self.class.exception_keys(e))
          raise
        end

        result
      end

      # Lifecycle events come from background threads, which a failing instrumenter must not stop.
      def notify(name, payload = {})
        @instrumenter.instrument(name, payload.merge(address: @address)) { nil }
      rescue StandardError => e
        Diagnostics.warn(@logger, "tarantool #{name} instrumentation failed: #{e.class}: #{e.message}")
      end
    end
  end
end
