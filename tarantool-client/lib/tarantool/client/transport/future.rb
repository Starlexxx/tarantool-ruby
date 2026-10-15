# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Result slot for one in-flight request. Thread::Queue#pop yields to the
      # Fiber Scheduler when one is active, so waiting never blocks other fibers.
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
          # One error object is shared by all failed futures; each waiter raises its own copy
          # so concurrent raises don't race on it.
          raise result.exception(result.message) if result.is_a?(Exception)

          result
        end
      end
    end
  end
end
