# frozen_string_literal: true

module Tarantool
  class Client
    # Tuple <-> Hash by the space format, for SpaceInfo. Fields beyond the format are keyed by their 0-based position.
    module TupleMapping
      def to_hash(tuple)
        hash = fields.each_with_index.to_h { |field, position| [field.name.to_sym, tuple[position]] }
        (fields.size...tuple.size).each { |position| hash[position] = tuple[position] }

        hash
      end

      # A missing field goes out as nil; on 3.x the server applies the field default to nil as well.
      def to_tuple(hash)
        positions = fields.each_with_index.to_h { |field, position| [field.name, position] }

        hash.each_with_object(Array.new(fields.size)) do |(key, value), tuple|
          tuple[position_of(key, positions)] = value
        end
      end

      private

      def position_of(key, positions)
        case key
        when Symbol, String
          positions.fetch(key.to_s) { raise ArgumentError, "space #{name} has no field '#{key}'" }
        when Integer then position_beyond_format(key)
        else raise ArgumentError, "unsupported key #{key.inspect} for space #{name}"
        end
      end

      def position_beyond_format(position)
        return position if position >= fields.size

        raise ArgumentError, "position #{position} is inside the format of space #{name}; use the field name"
      end
    end
  end
end
