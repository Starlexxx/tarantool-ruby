# frozen_string_literal: true

module Tarantool
  class Client
    # Format and indexes of a space from the loaded schema. `indexes` maps names to IndexInfo in id order.
    SpaceInfo = Data.define(:id, :name, :fields, :indexes) do
      def self.from_tuples(space, index_tuples)
        id, _owner, name, _engine, _field_count, _flags, format = space
        fields = (format || []).map { |raw| SpaceInfo::Field.from_raw(raw) }
        indexes = index_tuples.map { |tuple| IndexInfo.from_tuple(tuple, fields) }.sort_by(&:id)
        new(id:, name:, fields:, indexes: indexes.to_h { |index| [index.name, index] })
      end

      def primary_index
        indexes.each_value.find { |index| index.id.zero? }
      end
    end

    SpaceInfo::Field = Data.define(:name, :type, :is_nullable) do
      # A format entry without a type accepts any value.
      def self.from_raw(raw)
        new(name: raw['name'], type: raw.fetch('type', 'any'), is_nullable: raw.fetch('is_nullable', false))
      end
    end
  end
end
