# frozen_string_literal: true

module Tarantool
  module Model
    module Storage
      # Storage over a Tarantool::Client or Client::Pool. `read` options go to get and select, `write` options
      # to insert, update and delete, verbatim. The format comes from the client's schema on every call, so
      # alter and reconnect are picked up without a cache here. Inside Model.transaction operations, including
      # space_info, go through the open stream.
      class Box
        DUPLICATE_KEY = 3

        def initialize(caller, read: {}, write: {})
          if [read, write].any? { |options| options.key?(:mode) } && !caller.is_a?(Tarantool::Client::Pool)
            raise ArgumentError, 'mode: needs a Tarantool::Client::Pool'
          end

          @caller = caller
          @read_options = read
          @write_options = write
        end

        def verify(space, attributes:, primary_key:)
          layout(space, read).verify!(attributes:, primary_key:)
        end

        def get(space, key)
          layout = layout(space, read)
          tuple = client.select(space, key, limit: 1, **read).first

          tuple && layout.to_row(tuple)
        end

        def insert(space, attributes)
          layout = layout(space, write)
          tuple = unique { client.insert(space, layout.to_tuple(attributes), **write) }

          layout.to_row(tuple)
        end

        def update(space, key, operations)
          layout = layout(space, write)
          tuple = unique { client.update(space, key, operations, **write) }

          tuple && layout.to_row(tuple)
        end

        def delete(space, key)
          layout = layout(space, write)
          tuple = client.delete(space, key, **write)

          tuple && layout.to_row(tuple)
        end

        def select(space, index:, key:, iterator:, limit:, after:)
          layout = layout(space, read)
          options = { index: index || 0, iterator:, after:, **read }
          options[:limit] = limit if limit

          client.select(space, key, **options).map { |tuple| layout.to_row(tuple) }
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

        def layout(space, options)
          Layout.new(client.space_info(space, **options.slice(:mode, :timeout)))
        end

        def unique
          yield
        rescue Tarantool::ServerError => e
          raise RecordNotUnique, e.message if e.code == DUPLICATE_KEY

          raise
        end
      end
    end
  end
end
