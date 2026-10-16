# frozen_string_literal: true

module Tarantool
  module Schema
    # Declaration keys are checked against a closed list, so an unsupported Tarantool option such as is_sync
    # fails loudly instead of looking applied.
    module Options
      module_function

      def check(given, allowed, context)
        unknown = given.keys - allowed
        return if unknown.empty?

        raise ArgumentError, "#{context}: unsupported #{unknown.map(&:inspect).join(', ')}"
      end

      def boolean(value, context)
        return value if [true, false].include?(value)

        raise ArgumentError, "#{context}: expected true or false, got #{value.inspect}"
      end
    end
  end
end
