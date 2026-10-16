# frozen_string_literal: true

module Tarantool
  class Client
    # What data operations return for each tuple, chosen with `as:`.
    # @api private
    module TupleShape
      SHAPES = %i[tuple hash row].freeze

      def self.check(shape)
        return if SHAPES.include?(shape)

        raise ArgumentError, "unknown as: #{shape.inspect}, expected one of #{SHAPES.join(', ')}"
      end

      def self.apply(shape, tuple, space_info)
        case shape
        when :hash then space_info.to_hash(tuple)
        when :row then Row.new(tuple:, attributes: space_info.to_hash(tuple))
        else tuple
        end
      end
    end
  end
end
