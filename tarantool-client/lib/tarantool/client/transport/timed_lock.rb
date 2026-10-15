# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Mutual exclusion whose wait is bounded by a deadline, which Mutex#synchronize can't do. Not reentrant.
      class TimedLock
        def initialize
          @mutex = Mutex.new
          @released = ConditionVariable.new
          @locked = false
        end

        # Async interrupts are held outside blocking waits, so none can land between taking the lock
        # and entering the block, where the lock would never be released.
        def synchronize(deadline, &block)
          Thread.handle_interrupt(Object => :on_blocking) do
            acquire(deadline)
            begin
              Thread.handle_interrupt(Object => :immediate, &block)
            ensure
              release
            end
          end
        end

        private

        def acquire(deadline)
          @mutex.synchronize do
            while @locked
              remaining = Deadline.remaining(deadline)
              raise TimeoutError, 'lock wait timed out' if remaining&.zero?

              @released.wait(@mutex, remaining)
            end
            @locked = true
          end
        end

        def release
          Thread.handle_interrupt(Object => :never) do
            @mutex.synchronize do
              @locked = false
              @released.signal
            end
          end
        end
      end
    end
  end
end
