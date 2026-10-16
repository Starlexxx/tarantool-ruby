# frozen_string_literal: true

module Tarantool
  class Client
    # Tuple <-> Hash by the space format, for SpaceInfo. Fields beyond the format are keyed by their 0-based position.
    # @api private
    module TupleMapping
      # A position this far past the format would otherwise let a huge Integer key allocate a giant Array.
      MAX_POSITIONS_BEYOND_FORMAT = 1024
      def to_hash(tuple)
        hash = fields.each_with_index.to_h { |field, position| [field.name.to_sym, tuple[position]] }
        (fields.size...tuple.size).each { |position| hash[position] = tuple[position] }

        hash
      end

      # A missing field goes out as nil; on 3.x the server applies the field default to nil as well.
      def to_tuple(hash)
        positions = fields.each_with_index.to_h { |field, position| [field.name, position] }
        named_positions = {}

        hash.each_with_object(Array.new(fields.size)) do |(key, value), tuple|
          position = position_of(key, positions)
          check_not_duplicate(key, position, named_positions)
          tuple[position] = value
        end
      end

      private

      def position_of(key, positions)
        case key
        when Symbol, String
          positions.fetch(key.to_s) { raise UnknownFieldError, "space #{name} has no field '#{key}'" }
        when Integer then position_beyond_format(key)
        else raise ArgumentError, "unsupported key #{key.inspect} for space #{name}"
        end
      end

      # Symbol and String keys for the same field share one position; either both or just one of them given twice
      # would otherwise overwrite silently.
      def check_not_duplicate(key, position, named_positions)
        return unless key.is_a?(Symbol) || key.is_a?(String)
        raise ArgumentError, "space #{name} field '#{fields[position].name}' given twice" if named_positions[position]

        named_positions[position] = true
      end

      def position_beyond_format(position)
        raise ArgumentError, "position #{position} is negative for space #{name}" if position.negative?

        if position < fields.size
          raise ArgumentError, "position #{position} is inside the format of space #{name}; use the field name"
        end

        if position >= fields.size + MAX_POSITIONS_BEYOND_FORMAT
          raise ArgumentError, "position #{position} is more than #{MAX_POSITIONS_BEYOND_FORMAT} past the format " \
                               "of space #{name}"
        end

        position
      end
    end
  end
end
