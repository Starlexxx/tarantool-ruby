# frozen_string_literal: true

module Tarantool
  class Client
    # Latest known schema of one connection. Concurrent reloads of the same stale schema collapse into one fetch.
    class SchemaCache
      attr_reader :schema

      def initialize(connection)
        @connection = connection
        @lock = Transport::TimedLock.new
      end

      def reload(stale = nil, timeout:)
        deadline = Transport::Deadline.after(timeout)
        @lock.synchronize(deadline) do
          return @schema unless @schema.equal?(stale)

          @schema = Schema.fetch(@connection, timeout: Transport::Deadline.remaining(deadline))
        end
      end

      # Takes no lock: a reload holding it may be waiting for the reconnect that installs this schema.
      def replace(schema)
        @schema = schema
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
