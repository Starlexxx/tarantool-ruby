# frozen_string_literal: true

module Tarantool
  class Client
    # Space and index name -> id lookup and space formats loaded from the _vspace and _vindex system views over one
    # connection. Its ids are valid only for the instance behind that connection.
    # @api private
    class Schema
      attr_reader :version, :connection

      def self.fetch(connection, timeout:)
        deadline = Transport::Deadline.after(timeout)
        spaces, indexes = [Protocol::Constants::VSPACE_ID, Protocol::Constants::VINDEX_ID].map do |space_id|
          connection.perform(select_all(space_id), timeout: Transport::Deadline.remaining(deadline))
        end

        new(version: spaces.schema_version, spaces: spaces.data, indexes: indexes.data, connection:)
      end

      def self.select_all(space_id)
        Protocol::Requests::Select.new(
          space_id:, index_id: 0, key: [], limit: Protocol::Constants::MAX_LIMIT, offset: 0, iterator: :all
        )
      end
      private_class_method :select_all

      def initialize(version:, spaces:, indexes:, connection: nil)
        @version = version
        @connection = connection
        @space_ids = spaces.to_h { |space| [space[2], space[0]] }
        @index_ids = indexes.to_h { |index| [[index[0], index[2]], index[1]] }
        @space_infos = build_space_infos(spaces, indexes)
      end

      def resolve(space, index)
        space_id = space_id(space)

        [space_id, index_id(space_id, index)]
      end

      def space_info(space)
        @space_infos.fetch(space_id(space)) { raise SchemaError, "space '#{space}' not found" }
      end

      private

      def build_space_infos(spaces, indexes)
        indexes_by_space = indexes.group_by(&:first)
        infos = spaces.map { |space| SpaceInfo.from_tuples(space, indexes_by_space.fetch(space.first, [])) }

        infos.to_h { |info| [info.id, info] }
      end

      def space_id(space)
        id = space.is_a?(Integer) ? space : @space_ids[space.to_s]
        return id if @space_infos.key?(id)

        raise SchemaError, "space '#{space}' not found"
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
