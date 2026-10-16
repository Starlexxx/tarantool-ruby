# frozen_string_literal: true

module Tarantool
  module Model
    module Storage
      # Storage over a Tarantool::Client or Client::Pool. `read` options go to get and select, `write` options
      # to insert, update and delete, verbatim. The client converts tuples by the format of the schema each request
      # ran against, so alter and reconnect are picked up without a cache here. Inside Model.transaction operations,
      # including space_info, go through the open stream.
      class Box
        ER_TUPLE_FOUND = 3
        private_constant :ER_TUPLE_FOUND

        def initialize(caller, read: {}, write: {})
          if [read, write].any? { |options| options.key?(:mode) } && !caller.is_a?(Tarantool::Client::Pool)
            raise ArgumentError, 'mode: needs a Tarantool::Client::Pool'
          end

          @caller = caller
          @read_options = read
          @write_options = write
        end

        def verify(space, attributes:, primary_key:)
          Layout.new(client.space_info(space, **read.slice(:mode, :timeout))).verify!(attributes:, primary_key:)
        end

        def get(space, key)
          row(client.select(space, key, limit: 1, as: :row, **read).first)
        end

        def insert(space, attributes)
          row(unique { client.insert(space, attributes, as: :row, **write) })
        end

        def update(space, key, operations)
          row(unique { client.update(space, key, operations, as: :row, **write) })
        end

        def delete(space, key)
          row(client.delete(space, key, as: :row, **write))
        end

        def select(space, index:, key:, iterator:, limit:, after:)
          options = { index: index || 0, iterator:, after:, as: :row, **read }
          options[:limit] = limit if limit

          client.select(space, key, **options).map { |found| row(found) }
        end

        # IPROTO has no count request, and calling box.space.X.index.Y:count needs execute grants
        # (lua_call on 3.x, universe on 2.11) that an application user usually lacks.
        def count(_space, **)
          raise NotSupportedError, 'Storage::Box does not count'
        end

        def transaction(**options, &block)
          @caller.transaction(**options) do |stream|
            Transactions.open(self, stream, &block)
          end
        end

        private

        def client
          Transactions.handle(self) || @caller
        end

        def read
          scoped(@read_options)
        end

        def write
          scoped(@write_options)
        end

        def scoped(options)
          Transactions.handle(self) ? options.except(:mode) : options
        end

        def row(found)
          found && Row.new(attributes: found.attributes, tuple: found.tuple)
        end

        def unique
          yield
        rescue Tarantool::ServerError => e
          raise RecordNotUnique, e.message if e.code == ER_TUPLE_FOUND

          raise
        end
      end
    end
  end
end
