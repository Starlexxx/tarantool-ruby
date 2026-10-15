# frozen_string_literal: true

module Tarantool
  class Client
    # Latest known schema, installed by #replace for each new connection. Concurrent reloads of the same
    # stale schema collapse into one fetch.
    class SchemaCache
      attr_reader :schema

      def initialize
        @lock = Transport::TimedLock.new
        @assign = Mutex.new
      end

      # Fetches over the stale schema's own connection. A reconnect may replace the schema meanwhile, and
      # its schema wins: the fetched one is kept only while the stale one is still current.
      def reload(stale, timeout:)
        deadline = Transport::Deadline.after(timeout)
        @lock.synchronize(deadline) do
          return @schema unless @schema.equal?(stale)

          fresh = Schema.fetch(stale.connection, timeout: Transport::Deadline.remaining(deadline))
          @assign.synchronize { @schema = fresh if @schema.equal?(stale) }
          @schema
        end
      end

      # Skips the TimedLock: a reload holding it may be waiting for the reconnect that installs this schema.
      def replace(schema)
        @assign.synchronize { @schema = schema }
      end

      # An unknown name may have been created after the last load, so it costs one reload.
      def resolve(space, index, deadline, schema = @schema)
        [schema, schema.resolve(space, index)]
      rescue SchemaError
        schema = reload(schema, timeout: Transport::Deadline.remaining(deadline))
        [schema, schema.resolve(space, index)]
      end
    end
  end
end
