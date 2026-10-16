# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # Update operators the model sends: '=' from save, '+' and '-' from the counters. Returns a new tuple.
        # @api private
        class Operations
          ARITHMETIC = %w[+ -].freeze

          def initialize(space_info)
            @names = space_info.fields.map(&:name)
          end

          def apply(tuple, operations)
            operations.each_with_object(tuple.dup) do |(operator, name, value), result|
              fieldno = @names.index(name.to_s) || raise(Violation.unknown_field(name))
              result[fieldno] = value_after(operator.to_s, name, result[fieldno], value)
            end
          end

          private

          def value_after(operator, name, current, value)
            return value if operator == '='
            unless ARITHMETIC.include?(operator)
              raise NotSupportedError, "MemoryStorage has no #{operator} update operator"
            end
            raise Violation.operand(operator, name) unless current.is_a?(Numeric) && value.is_a?(Numeric)

            current.public_send(operator, value)
          end
        end
      end
    end
  end
end
