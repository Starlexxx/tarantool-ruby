# frozen_string_literal: true

module Tarantool
  class Client
    # Subscription returned by Client#watch.
    class Watcher
      FATAL_ERRORS = [NoMemoryError, SignalException, SystemExit].freeze
      private_constant :FATAL_ERRORS

      attr_reader :key

      def initialize(key, watchers, callback)
        @key = key
        @watchers = watchers
        @callback = callback
        @active = true
        @notified = false
      end

      def unwatch
        @active = false
        @watchers.remove(self)

        nil
      end

      # @api private
      def notified? = @notified

      # Callbacks share one dispatcher thread, so only an error meant to end the process may stop it.
      # @api private
      def notify(value)
        return unless @active

        @notified = true

        @callback.call(key, value)
      rescue *FATAL_ERRORS
        raise
      rescue Exception => e
        warn("tarantool watcher #{key.inspect} failed: #{e.class}: #{e.message}")
      end
    end
  end
end
