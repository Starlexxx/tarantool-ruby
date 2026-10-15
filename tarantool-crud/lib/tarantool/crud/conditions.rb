# frozen_string_literal: true

module Tarantool
  module Crud
    # Converts Array or Hash conditions into crud's [[operator, field, value]] form.
    module Conditions
      OPERATORS = %w[< <= == = >= >].freeze

      class << self
        def build(conditions)
          case conditions
          when nil then nil
          when Hash then conditions.flat_map { |field, value| from_pair(field.to_s, value) }
          else conditions.map { |operator, field, value| [check(operator.to_s), stringify(field), value] }
          end
        end

        private

        def from_pair(field, value)
          return [['==', field, value]] unless value.is_a?(Range)

          bounds = []
          bounds << ['>=', field, value.begin] unless value.begin.nil?
          bounds << [value.exclude_end? ? '<' : '<=', field, value.end] unless value.end.nil?
          bounds
        end

        def check(operator)
          return operator if OPERATORS.include?(operator)

          raise ArgumentError, "unknown condition operator: #{operator}"
        end

        def stringify(field) = field.is_a?(Symbol) ? field.to_s : field
      end
    end
  end
end
