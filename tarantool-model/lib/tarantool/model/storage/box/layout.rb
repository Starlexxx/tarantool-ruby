# frozen_string_literal: true

module Tarantool
  module Model
    module Storage
      class Box
        # Checks a model against the space format.
        # @api private
        class Layout
          def initialize(space_info)
            @space_info = space_info
            @names = space_info.fields.map { |field| field.name.to_sym }
          end

          def verify!(attributes:, primary_key:)
            missing = attributes - @names
            raise SchemaMismatchError, "space #{@space_info.name} has no field #{missing.join(', ')}" if missing.any?
            raise SchemaMismatchError, "space #{@space_info.name} has no primary index" unless @space_info.primary_index

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
