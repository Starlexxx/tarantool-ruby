# frozen_string_literal: true

module Tarantool
  module Schema
    # A space as the server has it, normalized to compare with a declaration: type aliases mapped, index types
    # downcased, missing nullability read as false. An empty Lua table may arrive as a map, hence Array().
    # @api private
    LiveSpace = Data.define(:engine, :format, :indexes) do
      def self.from_eval(raw)
        format = Array(raw['format']).map do |field|
          FieldSpec.new(name: field.fetch('name').to_sym, type: Types.live(field.fetch('type', 'any')),
                        is_nullable: field.fetch('is_nullable', false))
        end
        indexes = Array(raw['indexes']).map { |index| LiveSpace::Index.from_eval(index, format) }

        new(engine: raw.fetch('engine'), format:, indexes: indexes.sort_by(&:id))
      end

      def index(name) = indexes.find { |index| index.name == name }

      def primary = indexes.find { |index| index.id.zero? }

      def fields = format.to_h { |field| [field.name, field] }
    end

    LiveSpace::Index = Data.define(:id, :name, :type, :unique, :parts, :sequence) do
      def self.from_eval(raw, format)
        new(id: raw.fetch('id'), name: raw.fetch('name').to_sym, type: raw.fetch('type').downcase,
            unique: raw.fetch('unique'), sequence: raw.fetch('sequence'),
            parts: Array(raw['parts']).map { |part| part_from_eval(part, format) })
      end

      # fieldno is 1-based; a part beyond the format has no field name.
      def self.part_from_eval(raw, format)
        fieldno = raw.fetch('fieldno')

        PartSpec.new(field: format[fieldno - 1]&.name || :"##{fieldno}", type: Types.live(raw.fetch('type')),
                     is_nullable: raw.fetch('is_nullable', false), path: raw['path'])
      end
      private_class_method :part_from_eval
    end
  end
end
