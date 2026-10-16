# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # Tuple <-> Hash by the space format. Fields beyond the format are keyed by their 0-based position.
        # @api private
        class TupleMapping
          def initialize(space_info)
            @name = space_info.name
            @names = space_info.fields.map(&:name)
            @positions = @names.each_with_index.to_h
          end

          def to_hash(tuple)
            hash = @names.each_with_index.to_h { |name, position| [name.to_sym, tuple[position]] }
            (@names.size...tuple.size).each { |position| hash[position] = tuple[position] }

            hash
          end

          def to_tuple(hash)
            hash.each_with_object(Array.new(@names.size)) do |(key, value), tuple|
              tuple[position_of(key)] = value
            end
          end

          private

          def position_of(key)
            case key
            when Symbol, String then named_position(key)
            when Integer then position_beyond_format(key)
            else raise ArgumentError, "unsupported key #{key.inspect} for space #{@name}"
            end
          end

          def named_position(key)
            @positions.fetch(key.to_s) { raise ArgumentError, "space #{@name} has no field '#{key}'" }
          end

          def position_beyond_format(position)
            return position if position >= @names.size

            raise ArgumentError, "position #{position} is inside the format of space #{@name}; use the field name"
          end
        end
      end
    end
  end
end
