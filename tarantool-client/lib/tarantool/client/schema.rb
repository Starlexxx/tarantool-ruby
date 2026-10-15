# frozen_string_literal: true

module Tarantool
  class Client
    # Space and index name -> id lookup loaded from the _vspace and _vindex system views.
    class Schema
      attr_reader :version

      def self.fetch(connection, timeout:)
        spaces = connection.perform(select_all(Protocol::Constants::VSPACE_ID), timeout:)
        indexes = connection.perform(select_all(Protocol::Constants::VINDEX_ID), timeout:)
        new(version: spaces.schema_version, spaces: spaces.data, indexes: indexes.data)
      end

      def self.select_all(space_id)
        Protocol::Requests::Select.new(
          space_id:, index_id: 0, key: [], limit: Protocol::Constants::MAX_LIMIT, offset: 0, iterator: :all
        )
      end
      private_class_method :select_all

      def initialize(version:, spaces:, indexes:)
        @version = version
        @space_ids = spaces.to_h { |space| [space[2], space[0]] }
        @index_ids = indexes.to_h { |index| [[index[0], index[2]], index[1]] }
      end

      def resolve(space, index)
        space_id = space_id(space)
        [space_id, index_id(space_id, index)]
      end

      private

      def space_id(space)
        return space if space.is_a?(Integer)

        @space_ids.fetch(space.to_s) { raise SchemaError, "space '#{space}' not found" }
      end

      def index_id(space_id, index)
        return index if index.is_a?(Integer)

        @index_ids.fetch([space_id, index.to_s]) do
          raise SchemaError, "index '#{index}' not found in space #{space_id}"
        end
      end
    end
  end
end
