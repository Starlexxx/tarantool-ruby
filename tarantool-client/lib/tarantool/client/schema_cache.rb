# frozen_string_literal: true

module Tarantool
  class Client
    # Latest known schema of one connection. Concurrent reloads of the same stale schema collapse into one fetch.
    class SchemaCache
      attr_reader :schema

      def initialize(connection)
        @connection = connection
        @lock = Mutex.new
      end

      def reload(stale = nil, timeout:)
        @lock.synchronize do
          return @schema unless @schema.equal?(stale)

          @schema = Schema.fetch(@connection, timeout:)
        end
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
