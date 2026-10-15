# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Single-assignment result slot. Thread::Queue#pop yields to the Fiber
      # Scheduler when one is active, so waiting never blocks other fibers.
      class Future
        def initialize
          @queue = Thread::Queue.new
        end

        def resolve(value)
          @queue.push(value)
        end

        def reject(error)
          @queue.push(error)
        end

        def value(timeout)
          result = @queue.pop(timeout:)
          raise TimeoutError, "no response within #{timeout}s" if result.nil?
          # The same error object is shared by every failed future; raising a copy keeps backtraces per waiter.
          raise result.exception(result.message) if result.is_a?(Exception)

          result
        end
      end
    end
  end
end
