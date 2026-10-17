# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Thread-safe table of in-flight requests keyed by IPROTO sync.
      # @api private
      class PendingRequests
        def initialize
          @lock = Mutex.new
          @emptied = ConditionVariable.new
          @futures = {}
          @last_sync = 0
          @failure = nil
        end

        def register
          @lock.synchronize do
            raise @failure.exception(@failure.message) if @failure

            sync = @last_sync += 1
            [sync, @futures[sync] = Future.new]
          end
        end

        def resolve(sync, response)
          delete(sync)&.resolve(response)
        end

        def push(sync, message)
          @lock.synchronize { @futures[sync] }&.push(message)
        end

        def delete(sync)
          @lock.synchronize do
            future = @futures.delete(sync)
            @emptied.broadcast if @futures.empty?

            future
          end
        end

        def size
          @lock.synchronize { @futures.size }
        end

        # True once no request is in flight, false at the deadline.
        def wait_empty(timeout)
          deadline = Deadline.after(timeout)

          @lock.synchronize do
            until @futures.empty?
              remaining = Deadline.remaining(deadline)
              return false if remaining&.zero?

              @emptied.wait(@lock, remaining)
            end

            true
          end
        end

        def failure
          @lock.synchronize { @failure }
        end

        # Returns whether this call recorded the failure; later calls keep the first one.
        def fail_all(error)
          first, failure, futures = @lock.synchronize do
            first = @failure.nil?
            @failure ||= error
            @emptied.broadcast
            [first, @failure, @futures.values.tap { @futures.clear }]
          end
          futures.each { |future| future.reject(failure) }

          first
        end
      end
    end
  end
end
