# frozen_string_literal: true

module Tarantool
  class Client
    # Joins an internal thread without re-raising the exception it died with: the failure has already
    # reached whoever was waiting on the thread, and closing must not fail because of it. An exception
    # raised in the joining thread itself while it waits still propagates.
    # @api private
    module ThreadJoin
      module_function

      def join(thread)
        thread&.join unless Thread.current == thread
      rescue Exception
        raise unless thread.status.nil?
      end
    end
  end
end
