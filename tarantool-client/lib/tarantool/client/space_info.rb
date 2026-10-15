# frozen_string_literal: true

module Tarantool
  class Client
    # Format and indexes of a space from the loaded schema. `indexes` maps names to IndexInfo in id order.
    SpaceInfo = Data.define(:id, :name, :fields, :indexes) do
      def self.from_tuples(space, index_tuples)
        fields = (space[6] || []).map { |raw| SpaceInfo::Field.from_raw(raw) }
        sorted = index_tuples.sort_by { |tuple| tuple[1] }
        indexes = sorted.to_h { |tuple| [tuple[2], IndexInfo.from_tuple(tuple, fields)] }
        new(id: space[0], name: space[2], fields:, indexes:)
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
