# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # Storage::Box behaviour: schema checks, a tuple on every row, transactions, no count, server errors.
        # @api private
        class BoxMode
          def verify(space, attributes:, primary_key:)
            space.layout.verify!(attributes:, primary_key:)
          end

          def sequences? = true

          def to_tuple(space, attributes)
            space.mapping.to_tuple(attributes)
          end

          def row(space, tuple, **)
            Row.new(attributes: space.mapping.to_hash(tuple), tuple:)
          end

          def error(violation, _operation)
            return Tarantool::SchemaError.new(violation.message) if %i[space index].include?(violation.kind)

            Tarantool::ServerError.new(violation.message, code: violation.code)
          end
        end
      end
    end
  end
end
