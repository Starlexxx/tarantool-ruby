# frozen_string_literal: true

module Tarantool
  class Client
    # execute(String) through the statement cache: PREPARE on a miss, EXECUTE by id, one fresh PREPARE when the
    # server no longer knows the id (the session changed under a cached entry). Ids belong to a session, so a
    # lost connection empties the cache; a stream has its own perform and does not use it.
    # @api private
    module CachedStatements
      ER_WRONG_QUERY_ID = 211
      private_constant :ER_WRONG_QUERY_ID

      def execute(sql, bindings = [], timeout: nil)
        return super unless @statement_cache && sql.is_a?(String)

        execute_cached(sql, bindings, timeout, retry_unknown: true)
      end

      private

      def execute_cached(sql, bindings, timeout, retry_unknown:)
        request = Protocol::Requests::Execute.new(statement: cached_statement_id(sql, timeout), bindings:)

        SqlResult.from_response(perform(request, timeout:))
      rescue ServerError => e
        raise unless retry_unknown && e.code == ER_WRONG_QUERY_ID

        @statement_cache.forget(sql)
        execute_cached(sql, bindings, timeout, retry_unknown: false)
      end

      def cached_statement_id(sql, timeout)
        id, evicted = @statement_cache.id_for(sql) { prepare(sql, timeout:).id }
        unprepare(evicted, timeout) if evicted

        id
      end

      # The evicted statement only holds server memory; a session that is gone took it along.
      def unprepare(id, timeout)
        perform(Protocol::Requests::Prepare.new(statement: id), timeout:)
      rescue Error
        nil
      end

      def forget_statements = @statement_cache&.clear
    end
  end
end
