# frozen_string_literal: true

module Tarantool
  class Client
    # Name lookup for one transaction, pinned to the schema version the server reported for BEGIN.
    # Re-resolving names against a newer schema mid-transaction could send later statements to a
    # different space than earlier ones, so a schema change fails the transaction instead.
    class TransactionSchema
      CHANGED = 'schema changed during the transaction; retry the whole transaction'

      attr_reader :version

      def initialize(cache, connection, version)
        @cache = cache
        @connection = connection
        @version = version
      end

      def resolve(space, index, deadline)
        pinned(deadline).resolve(space, index)
      end

      def space_info(space, deadline)
        pinned(deadline).space_info(space)
      end

      # A request rejected for its schema version did not run, so the transaction still rolls back
      # cleanly. The reload spares the retried transaction the same rejection.
      def raise_changed(deadline)
        schema = @cache.schema
        reload(schema, deadline) if schema.version == version
        raise TransactionError, CHANGED
      end

      private

      # A cache older than BEGIN was stale before the transaction started and may catch up;
      # anything newer means the schema changed after BEGIN. A schema of another connection means
      # this one was lost, and the versions of two instances can't be compared.
      def pinned(deadline)
        schema = @cache.schema
        raise TransactionError, Stream::LOST unless schema.connection.equal?(@connection)

        schema = reload(schema, deadline) if schema.version < version
        raise TransactionError, CHANGED unless schema.version == version

        schema
      end

      def reload(schema, deadline)
        @cache.reload(schema, timeout: Transport::Deadline.remaining(deadline))
      end
    end
  end
end
