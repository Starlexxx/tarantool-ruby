# frozen_string_literal: true

module Tarantool
  class Client
    # Server-side statement ids by SQL text, least recently used first. The PREPARE runs outside the lock, so
    # two threads missing the same text may both prepare: the later id wins and the earlier one comes back as
    # evicted, for the caller to unprepare.
    # @api private
    class StatementCache
      def initialize(limit)
        @limit = limit
        @lock = Mutex.new
        @ids = {}
      end

      # [id, evicted id or nil]; the block prepares the statement on a miss.
      def id_for(sql)
        id = @lock.synchronize { hit(sql) }
        return [id, nil] if id

        store(sql, yield)
      end

      def forget(sql)
        @lock.synchronize { @ids.delete(sql) }
      end

      def clear
        @lock.synchronize { @ids.values.tap { @ids.clear } }
      end

      private

      def hit(sql)
        id = @ids.delete(sql)
        @ids[sql] = id if id

        id
      end

      def store(sql, id)
        @lock.synchronize do
          evicted = @ids.delete(sql)
          evicted = @ids.delete(@ids.keys.first) if evicted.nil? && @ids.size >= @limit
          @ids[sql] = id

          [id, evicted]
        end
      end
    end
  end
end
