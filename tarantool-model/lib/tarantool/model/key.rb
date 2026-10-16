# frozen_string_literal: true

module Tarantool
  module Model
    # Index keys are Arrays; Kernel#Array would split a Time or a Hash.
    # @api private
    module Key
      def self.wrap(value)
        value.is_a?(Array) ? value : [value]
      end
    end
  end
end
