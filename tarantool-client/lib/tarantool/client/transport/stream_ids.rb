# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Thread-safe allocator of unique, non-zero IPROTO stream ids.
      class StreamIds
        def initialize
          @lock = Mutex.new
          @last_id = 0
        end

        def next
          @lock.synchronize { @last_id += 1 }
        end
      end
    end
  end
end
