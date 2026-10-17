# frozen_string_literal: true

module Tarantool
  module Model
    module Storage
      # Storage over a Tarantool::Crud::Client; read/write defaults live in that client. crud has no schema
      # lookup, so the format is not checked and `index: nil` means the index named `primary_index:`. crud
      # reads an unknown index name as a field name and returns nothing, so that name must be right.
      # Single-row operations return no tuple; only select rows can be continued after.
      class Crud
        OPERATORS = { eq: '==', ge: '>=', gt: '>', le: '<=', lt: '<' }.freeze
        DUPLICATE_KEY = /Duplicate key exists/

        # tarantool-model doesn't depend on tarantool-crud, yet rescues its errors.
        def initialize(crud, primary_index: :primary)
          raise Error, "tarantool-crud is not loaded; require 'tarantool/crud'" unless defined?(Tarantool::Crud)

          @crud = crud
          @primary_index = primary_index
        end

        def verify(*, **) = nil

        def get(space, key)
          row(@crud.space(space).get(key))
        end

        def insert(space, attributes)
          row(unique { @crud.space(space).insert(attributes) })
        end

        def update(space, key, operations)
          row(unique { @crud.space(space).update(key, operations) })
        end

        def delete(space, key)
          row(@crud.space(space).delete(key))
        end

        def select(space, index:, key:, iterator:, limit:, after:)
          options = { first: limit, after: }.compact
          result = @crud.space(space).select(conditions(index, key, iterator), **options)

          result.zip(result.tuples).map { |attributes, tuple| Row.new(attributes:, tuple:) }
        end

        def count(space, index:, key:, iterator:)
          @crud.space(space).count(conditions(index, key, iterator))
        end

        def supports_transactions? = false

        def transaction(**)
          raise NotSupportedError, 'crud has no interactive transactions'
        end

        private

        def row(attributes)
          attributes && Row.new(attributes:, tuple: nil)
        end

        def conditions(index, key, iterator)
          return if iterator == :all

          operator = OPERATORS.fetch(iterator) { raise ArgumentError, "crud has no condition for #{iterator.inspect}" }
          return if key.empty?

          [[operator, (index || @primary_index).to_s, key]]
        end

        def unique
          yield
        rescue Tarantool::Crud::InsertError, Tarantool::Crud::UpdateError => e
          raise RecordNotUnique, e.message if e.message.match?(DUPLICATE_KEY)

          raise
        end
      end
    end
  end
end
