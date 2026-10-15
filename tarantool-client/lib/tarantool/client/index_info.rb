# frozen_string_literal: true

module Tarantool
  class Client
    # One index of a space as listed in _vindex.
    IndexInfo = Data.define(:id, :name, :type, :unique, :parts) do
      def self.from_tuple(tuple, fields)
        opts = tuple[4] || {}
        parts = (tuple[5] || []).map { |raw| IndexInfo::Part.from_raw(raw, fields) }
        new(id: tuple[1], name: tuple[2], type: tuple[3], unique: opts.fetch('unique', true), parts:)
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
