# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Result slot for one in-flight request, also carrying its pushed messages. Thread::Queue#pop
      # yields to the Fiber Scheduler when one is active, so waiting never blocks other fibers.
      class Future
        Push = Data.define(:message)
        private_constant :Push

        MAX_UNREAD_PUSHES = 10_000
        private_constant :MAX_UNREAD_PUSHES

        def initialize
          @queue = Thread::Queue.new
          @overflow = false
        end

        def resolve(value)
          @queue.push(value)
        end

        def reject(error)
          @queue.push(error)
        end

        def push(message)
          return if @overflow

          if @queue.size >= MAX_UNREAD_PUSHES
            @overflow = true
            @queue.push(ProtocolError.new('too many unread push messages'))
            return
          end

          @queue.push(Push.new(message))
        end

        # Yields each pushed message, in the waiting thread, until the final value arrives.
        def value(timeout)
          deadline = Deadline.after(timeout)

          loop do
            result = @queue.pop(timeout: Deadline.remaining(deadline))
            raise TimeoutError, "no response within #{timeout}s" if result.nil?
            # One error object is shared by all failed futures; each waiter raises its own copy
            # so concurrent raises don't race on it.
            raise result.exception(result.message) if result.is_a?(Exception)
            return result unless result.is_a?(Push)

            yield result.message if block_given?
          end
        end
      end
    end
  end
end
