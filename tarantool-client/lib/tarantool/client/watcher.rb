# frozen_string_literal: true

module Tarantool
  class Client
    # Subscription returned by Client#watch.
    class Watcher
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

      # @api private
      def notify(value)
        return unless @active

        @notified = true

        CallbackGuard.run("tarantool watcher #{key.inspect}") { @callback.call(key, value) }
      end
    end
  end
end
