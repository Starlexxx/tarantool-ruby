# frozen_string_literal: true

module Tarantool
  class Client
    class Instrumentation
      # A logger as an instrumenter, around the user's instrumenter if there is one. The request line is built
      # only when the logger takes debug.
      # @api private
      class LogInstrumenter
        def initialize(logger, instrumenter)
          @logger = logger
          @instrumenter = instrumenter
        end

        def instrument(name, payload, &)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          @instrumenter ? @instrumenter.instrument(name, payload, &) : yield
        ensure
          log(name, payload, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
        end

        private

        def log(name, payload, duration)
          level = LogLines.level(name)

          @logger.public_send(level) { LogLines.line(name, payload, duration) } if level
        rescue StandardError => e
          Kernel.warn("tarantool logger failed: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
