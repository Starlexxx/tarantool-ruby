# frozen_string_literal: true

module Tarantool
  class Client
    # Watchers of one client over IPROTO_WATCH. The server tracks keys, not watchers: WATCH goes
    # out for the first watcher of a key and UNWATCH after the last. Callbacks run on one
    # dispatcher thread so they never stall the reader; the ack (WATCH again) follows them, letting
    # the server coalesce changes made meanwhile. Watched keys outlive the socket so a reconnect
    # can subscribe to them again. A key has at most one event queued: a newer value replaces the
    # pending one, as the server itself only promises the latest.
    # @api private
    class Watchers
      def initialize(link, timeout:)
        @link = link
        @timeout = timeout
        @lock = Mutex.new
        @watchers = {}
        @values = {}
        @pending = {}
        @dispatcher = Dispatcher.new
      end

      def add(key, callback)
        watcher = Watcher.new(key, self, callback)
        @lock.synchronize do
          send_request(Protocol::Requests::Watch.new(key:)) unless @watchers.key?(key)
          (@watchers[key] ||= []) << watcher
        end
        @dispatcher.push { catch_up(watcher) }

        watcher
      end

      # Errors are swallowed: the watcher is already gone locally, and a server-side subscription left
      # behind by an unsent UNWATCH yields at most one event, which is ignored and never acked.
      def remove(watcher)
        @lock.synchronize do
          watchers = @watchers[watcher.key]
          next unless watchers&.delete(watcher) && watchers.empty?

          @watchers.delete(watcher.key)
          @values.delete(watcher.key)
          @pending.delete(watcher.key)
          send_request(Protocol::Requests::Unwatch.new(key: watcher.key))
        end
      rescue Error
        nil
      end

      def dispatch(key, value)
        @lock.synchronize do
          next unless @watchers.key?(key)

          queued = @pending.key?(key)
          @pending[key] = value
          @dispatcher.push { deliver(key) } unless queued
        end
      end

      # Runs the block on the dispatcher after the events queued so far.
      def defer(&job)
        @dispatcher.push { CallbackGuard.run('tarantool watchers: deferred job', &job) }
      end

      # A new session has no subscriptions. WATCH also makes the server send each key's current value,
      # so watchers learn what changed while the client was away. A failed key does not skip the rest.
      def resubscribe(connection)
        @lock.synchronize do
          @watchers.each_key do |key|
            connection.notify(Protocol::Requests::Watch.new(key:), timeout: @timeout)
          rescue Error
            nil
          end
        end
      end

      # Registrations survive a fork; values and the dispatcher are per process and come back after resubscribe.
      def restart_after_fork(new_link)
        @link = new_link
        @values = {}
        @pending = {}
        @dispatcher = Dispatcher.new
      end

      def close
        @dispatcher.close
        @lock.synchronize do
          @watchers.clear
          @values.clear
          @pending.clear
        end
      end

      private

      def deliver(key)
        watchers, value = take_pending(key)
        return unless watchers

        watchers.each { |watcher| watcher.notify(value) }

        acknowledge(key)
      end

      # A job can outlive its event: the key may have been unwatched, and watched again, since it was queued.
      def take_pending(key)
        @lock.synchronize do
          next unless @pending.key?(key)

          value = @values[key] = @pending.delete(key)
          [@watchers[key].dup, value]
        end
      end

      # The server sends a key's value once per WATCH, so a watcher joining a watched key
      # gets the cached one, unless an event queued before this job already reached it.
      def catch_up(watcher)
        known, value = @lock.synchronize { [@values.key?(watcher.key), @values[watcher.key]] }

        watcher.notify(value) if known && !watcher.notified?
      end

      # Failure means the connection is gone, and the subscription with it.
      def acknowledge(key)
        @lock.synchronize do
          send_request(Protocol::Requests::Watch.new(key:)) if @watchers.key?(key)
        end
      rescue Error
        nil
      end

      def send_request(request)
        @link.notify(request, timeout: @timeout)
      end
    end
  end
end
