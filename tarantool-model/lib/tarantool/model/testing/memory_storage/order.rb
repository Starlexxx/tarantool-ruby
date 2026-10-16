# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # Tree index order of keys of equal length: nil first, as MP_NIL, then false before true, then Ruby's
        # <=>. Values Ruby cannot compare, such as mixed types in a scalar field, raise ArgumentError.
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
            return nil_rank(left) <=> nil_rank(right) if left.nil? || right.nil?
            return as_int(left) <=> as_int(right) if boolean?(left) && boolean?(right)

            (left <=> right) || raise(ArgumentError, "MemoryStorage cannot order #{left.inspect} and #{right.inspect}")
          end

          def nil_rank(value)
            value.nil? ? 0 : 1
          end

          def boolean?(value)
            [true, false].include?(value)
          end

          def as_int(value)
            value ? 1 : 0
          end
        end
      end
    end
  end
end
