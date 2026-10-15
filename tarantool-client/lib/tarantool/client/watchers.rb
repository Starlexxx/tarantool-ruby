# frozen_string_literal: true

module Tarantool
  class Client
    # Watchers of one client over IPROTO_WATCH. The server tracks keys, not watchers: WATCH goes
    # out for the first watcher of a key and UNWATCH after the last. Callbacks run on one
    # dispatcher thread so they never stall the reader; the ack (WATCH again) follows them, letting
    # the server coalesce changes made meanwhile. Watched keys outlive the socket so a reconnect
    # can subscribe to them again.
    class Watchers
      def initialize(connection, timeout:)
        @connection = connection
        @timeout = timeout
        @lock = Mutex.new
        @watchers = {}
        @values = {}
        @jobs = Thread::Queue.new
      end

      def add(key, callback)
        watcher = Watcher.new(key, self, callback)
        @lock.synchronize do
          @dispatcher ||= start_dispatcher
          send_request(Protocol::Requests::Watch.new(key:)) unless @watchers.key?(key)
          (@watchers[key] ||= []) << watcher
        end
        @jobs.push(-> { catch_up(watcher) })
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
          send_request(Protocol::Requests::Unwatch.new(key: watcher.key))
        end
      rescue Error
        nil
      end

      def dispatch(key, value)
        @jobs.push(-> { deliver(key, value) })
      end

      # A new session has no subscriptions. WATCH also makes the server send each key's current value,
      # so watchers learn what changed while the client was away.
      def resubscribe(connection)
        @lock.synchronize do
          @watchers.each_key { |key| connection.notify(Protocol::Requests::Watch.new(key:), timeout: @timeout) }
        end
      rescue Error
        nil
      end

      def close
        @jobs.clear
        @jobs.close
        @lock.synchronize do
          @watchers.clear
          @values.clear
        end
        @dispatcher&.join unless Thread.current == @dispatcher
      end

      private

      def start_dispatcher
        Thread.new { run }.tap { |thread| thread.name = 'tarantool-watchers' }
      end

      def run
        while (job = @jobs.pop)
          job.call
        end
      end

      def deliver(key, value)
        watchers = @lock.synchronize do
          next [] unless @watchers.key?(key)

          @values[key] = value
          @watchers[key].dup
        end
        return if watchers.empty?

        watchers.each { |watcher| run_callback(watcher, value) }
        acknowledge(key)
      end

      # The server sends a key's value once per WATCH, so a watcher joining a watched key
      # gets the cached one, unless an event queued before this job already reached it.
      def catch_up(watcher)
        known, value = @lock.synchronize { [@values.key?(watcher.key), @values[watcher.key]] }
        run_callback(watcher, value) if known && !watcher.notified?
      end

      def run_callback(watcher, value)
        watcher.notify(value)
      rescue StandardError => e
        warn("tarantool watcher #{watcher.key.inspect} failed: #{e.class}: #{e.message}")
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
        @connection.notify(request, timeout: @timeout)
      end
    end
  end
end
