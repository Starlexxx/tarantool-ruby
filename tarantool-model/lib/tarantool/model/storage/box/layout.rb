# frozen_string_literal: true

module Tarantool
  module Model
    module Storage
      class Box
        # Field order of a space: converts attribute Hashes to tuples and back, and checks a model against the
        # format. Fields the model does not declare go out as nil and are ignored on read.
        class Layout
          def initialize(space_info)
            @space_info = space_info
            @names = space_info.fields.map { |field| field.name.to_sym }
          end

          def to_tuple(attributes)
            @names.map { |name| attributes[name] }
          end

          def to_row(tuple)
            Row.new(attributes: @names.zip(tuple).to_h, tuple:)
          end

          def verify!(attributes:, primary_key:)
            missing = attributes - @names
            raise SchemaMismatchError, "space #{@space_info.name} has no field #{missing.join(', ')}" if missing.any?

            return if primary_key == primary_parts

            raise SchemaMismatchError,
                  "primary key #{primary_key.inspect} does not match the parts of index 0: #{primary_parts.inspect}"
          end

          private

          def primary_parts
            @space_info.primary_index&.parts&.map { |part| part.name&.to_sym }
          end
        end
      end
    end
  end
end
