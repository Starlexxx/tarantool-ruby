# frozen_string_literal: true

module Tarantool
  class Client
    # One index of a space as listed in _vindex.
    IndexInfo = Data.define(:id, :name, :type, :unique, :parts) do
      def self.from_tuple(tuple, fields)
        _space_id, id, name, type, opts, parts = tuple

        new(
          id:, name:, type:, unique: (opts || {}).fetch('unique', true),
          parts: (parts || []).map { |raw| IndexInfo::Part.from_raw(raw, fields) }
        )
      end
    end

    # `fieldno` is 0-based; `name` comes from the space format and is nil for a field beyond it.
    IndexInfo::Part = Data.define(:fieldno, :name, :type, :is_nullable, :path) do
      # _vindex keeps parts either as [fieldno, type] or as a map with nullability and a JSON path.
      def self.from_raw(raw, fields)
        fieldno, type, is_nullable, path = raw.is_a?(Hash) ? raw.values_at('field', 'type', 'is_nullable', 'path') : raw

        new(fieldno:, name: fields[fieldno]&.name, type:, is_nullable: is_nullable || false, path:)
      end
    end
  end
end
