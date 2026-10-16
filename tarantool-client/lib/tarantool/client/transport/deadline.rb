# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Monotonic-clock deadlines. A nil timeout gives a nil deadline, which never expires.
      # @api private
      module Deadline
        module_function

        def after(timeout) = timeout && (now + timeout)
        def remaining(deadline) = deadline && [deadline - now, 0].max
        def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
