# frozen_string_literal: true

module Tarantool
  module Crud
    # crud.schema output in the shape tarantool-schema declares and MemoryStorage accepts: Symbol names,
    # String types, indexes as an Array in id order, parts named by field. exclude_null is dropped.
    # @api private
    module Schema
      module_function

      def all(raw) = raw.to_h { |name, space| [name.to_sym, space(space)] }

      def space(raw)
        format = Array(raw['format']).map { |field| field(field) }
        indexes = Array(raw['indexes']&.values).sort_by { |index| index['id'] }

        { format:, indexes: indexes.map { |index| index(index, format) } }
      end

      def field(raw)
        { name: raw.fetch('name').to_sym, type: raw.fetch('type', 'any'), is_nullable: raw.fetch('is_nullable', false) }
      end

      def index(raw, format)
        { name: raw.fetch('name').to_sym, type: raw.fetch('type').downcase, unique: raw.fetch('unique'),
          parts: Array(raw['parts']).map { |part| part(part, format) } }
      end

      def part(raw, format)
        fieldno = raw.fetch('fieldno')
        field = format[fieldno - 1]&.fetch(:name) || :"##{fieldno}"
        part = { field:, type: raw.fetch('type'), is_nullable: raw.fetch('is_nullable', false) }
        part[:path] = raw['path'] if raw['path']

        part
      end
    end
  end
end
