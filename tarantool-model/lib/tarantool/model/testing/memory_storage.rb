# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      # In-memory storage for application tests, without a Tarantool server. Spaces are declared in
      # tarantool-schema's ensure_space shape. `behaves_like: :box` keeps the Storage::Box contract, `:crud` the
      # Storage::Crud one: what the server would reject is raised with the classes and codes the application sees
      # in production. The README lists what it does not model.
      class MemoryStorage
        MODES = { box: BoxMode, crud: CrudMode }.freeze
        private_constant :MODES

        def self.from_definition(definition, **)
          new(definition.to_h, **)
        end

        def initialize(spaces, behaves_like: :box)
          @mode = MODES.fetch(behaves_like) do
            raise ArgumentError, "behaves_like must be one of #{MODES.keys.join(', ')}, got #{behaves_like.inspect}"
          end.new
          Keys.distinct!(spaces.keys.map(&:to_s), 'MemoryStorage')
          @spaces = spaces.to_h { |name, schema| [name.to_s, build_space(name, schema)] }
        end

        def verify(space, attributes:, primary_key:)
          @mode.verify(attributes:, primary_key:) { perform(space, :get, &:itself) }
        end

        def get(space, key)
          single(space, :get) { |table| @mode.get(table, key) }
        end

        def insert(space, attributes)
          single(space, :insert) { |table| table.insert(@mode.to_tuple(table, attributes)) }
        end

        def update(space, key, operations)
          single(space, :update) { |table| table.update(key, operations) }
        end

        def delete(space, key)
          single(space, :delete) { |table| table.delete(key) }
        end

        def select(space, index:, key:, iterator:, limit:, after:)
          perform(space, :select) do |table|
            tuples = @mode.scan(table, index:, key:, iterator:, after:)

            (limit ? tuples.first(limit) : tuples).map { |tuple| @mode.row(table, tuple, single: false) }
          end
        end

        def count(space, index:, key:, iterator:)
          @mode.count!

          perform(space, :count) { |table| @mode.scan(table, index:, key:, iterator:, after: nil).size }
        end

        # Writes apply at once; the rows are restored unless the block finishes normally. `isolation:` and
        # `timeout:` are accepted and ignored. Sequences are not restored, as in Tarantool.
        def transaction(**, &)
          @mode.transaction!
          raise Tarantool::TransactionError, 'nested transactions are not supported' if Transactions.handle(self)

          snapshots = @spaces.transform_values(&:snapshot)
          committed = false
          Transactions.open(self, :memory, &).tap { committed = true }
        ensure
          snapshots&.each { |name, rows| @spaces.fetch(name).restore(rows) } unless committed
        end

        private

        def perform(space, operation)
          yield @spaces.fetch(space.to_s) { raise Violation.unknown_space(space) }
        rescue Violation => e
          raise @mode.error(e, operation)
        end

        def single(space, operation)
          perform(space, operation) do |table|
            tuple = yield table

            tuple && @mode.row(table, tuple, single: true)
          end
        end

        def build_space(name, schema)
          declaration = Declaration.new(name, schema)

          Space.new(declaration.space_info, sequence: declaration.sequence && @mode.sequences?)
        end
      end
    end
  end
end
