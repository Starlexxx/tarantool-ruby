# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Thread-safe table of in-flight requests keyed by IPROTO sync.
      class PendingRequests
        def initialize
          @lock = Mutex.new
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

        def delete(sync)
          @lock.synchronize { @futures.delete(sync) }
        end

        def failure
          @lock.synchronize { @failure }
        end

        def fail_all(error)
          failure, futures = @lock.synchronize do
            @failure ||= error
            [@failure, @futures.values.tap { @futures.clear }]
          end
          futures.each { |future| future.reject(failure) }
        end
      end
    end
  end
end
