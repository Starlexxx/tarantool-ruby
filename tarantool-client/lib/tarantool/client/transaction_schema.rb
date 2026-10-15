# frozen_string_literal: true

module Tarantool
  class Client
    # Name lookup for one transaction, pinned to the schema version the server reported for BEGIN.
    # Re-resolving names against a newer schema mid-transaction could send later statements to a
    # different space than earlier ones, so a schema change fails the transaction instead.
    class TransactionSchema
      CHANGED = 'schema changed during the transaction; retry the whole transaction'

      attr_reader :version

      def initialize(cache, version)
        @cache = cache
        @version = version
      end

      def resolve(space, index, deadline)
        pinned(deadline).resolve(space, index)
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
      # anything newer means the schema changed after BEGIN.
      def pinned(deadline)
        schema = @cache.schema
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
