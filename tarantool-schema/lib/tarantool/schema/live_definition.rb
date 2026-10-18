# frozen_string_literal: true

module Tarantool
  module Schema
    # The ensure_space arguments that declare a live space as it is. A part is written as a bare field name when
    # it inherits everything from the field, so the result reads like a hand-written declaration.
    # @api private
    module LiveDefinition
      module_function

      def arguments(name, live)
        fields = live.fields

        { engine: live.engine, format: live.format.map(&:to_h),
          indexes: live.indexes.map { |index| index_arguments(name, index, fields) } }
      end

      # Grants whose privileges the DSL does not know (execute on 2.11) are left out.
      def grants(live)
        live.masks.to_h { |user, mask| [user.to_sym, Privileges.names(mask)] }.reject { |_, names| names.empty? }
      end

      def index_arguments(space, index, fields)
        raise ArgumentError, "space #{space}: index #{index.name} is functional, not supported" if index.func

        { name: index.name, type: index.type, unique: index.unique, sequence: index.sequence,
          parts: index.parts.map { |part| part_argument(space, index, part, fields) } }
      end

      def part_argument(space, index, part, fields)
        field = fields[part.field]
        raise ArgumentError, "space #{space}: index #{index.name}: part #{part.field} is beyond the format" unless field

        part.path ? path_part(part, field) : plain_part(part, field)
      end

      def plain_part(part, field)
        differing = { type: part.type, is_nullable: part.is_nullable }.reject { |key, value| field.send(key) == value }

        differing.empty? ? part.field : { field: part.field, **differing }
      end

      # A path part always declares its type; nullability still inherits from the field.
      def path_part(part, field)
        nullable = part.is_nullable == field.is_nullable ? {} : { is_nullable: part.is_nullable }

        { field: part.field, type: part.type, **nullable, path: part.path }
      end
    end
  end
end
