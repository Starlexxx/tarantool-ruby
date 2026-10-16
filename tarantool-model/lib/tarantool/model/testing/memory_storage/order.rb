# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # Tree index order of keys of equal length: nil first, as MP_NIL, then Ruby's <=>. Values Ruby cannot
        # compare, such as mixed types in a scalar field or booleans, raise ArgumentError.
        # @api private
        module Order
          module_function

          def compare(left, right)
            left.zip(right).each do |a, b|
              result = value(a, b)
              return result unless result.zero?
            end

            0
          end

          def value(left, right)
            return (left.nil? ? 0 : 1) <=> (right.nil? ? 0 : 1) if left.nil? || right.nil?

            (left <=> right) || raise(ArgumentError, "MemoryStorage cannot order #{left.inspect} and #{right.inspect}")
          end
        end
      end
    end
  end
end
