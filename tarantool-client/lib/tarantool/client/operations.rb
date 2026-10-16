# frozen_string_literal: true

module Tarantool
  class Client
    # Data operations, call, eval and SQL. Includers implement `perform(request, timeout:, on_push: nil)`,
    # `perform_on_space(space, index, timeout:, format: false) { |space_id, index_id, space_info| request }`, which
    # returns the response to the request built by the block, and `lookup_space(space, timeout)`, which returns its
    # SpaceInfo. With `format: true` the block gets the SpaceInfo of the schema the request is resolved and
    # version-checked against, even for numeric ids; otherwise the third argument may be absent.
    # @api private
    module Operations
      def ping(timeout: nil)
        perform(Protocol::Requests::Ping.new, timeout:)

        true
      end

      def space_info(space, timeout: nil)
        lookup_space(space, timeout)
      end

      def select(space, key = [], index: 0, limit: Protocol::Constants::MAX_LIMIT, offset: 0, iterator: :eq,
                 after: nil, as: :tuple, timeout: nil)
        on_space(space, index, as:, timeout:) do |space_id, index_id|
          Protocol::Requests::Select.new(space_id:, index_id:, key: key_tuple(key), limit:, offset:, iterator:, after:)
        end
      end

      def insert(space, tuple, as: :tuple, timeout: nil)
        on_space(space, 0, as:, timeout:, format: tuple.is_a?(Hash)) do |space_id, _index_id, space_info|
          Protocol::Requests::Insert.new(space_id:, tuple: tuple_for(tuple, space_info))
        end.first
      end

      def replace(space, tuple, as: :tuple, timeout: nil)
        on_space(space, 0, as:, timeout:, format: tuple.is_a?(Hash)) do |space_id, _index_id, space_info|
          Protocol::Requests::Replace.new(space_id:, tuple: tuple_for(tuple, space_info))
        end.first
      end

      def update(space, key, operations, index: 0, as: :tuple, timeout: nil)
        on_space(space, index, as:, timeout:) do |space_id, index_id|
          Protocol::Requests::Update.new(space_id:, index_id:, key: key_tuple(key), operations:)
        end.first
      end

      def upsert(space, tuple, operations, timeout: nil)
        perform_on_space(space, 0, timeout:, format: tuple.is_a?(Hash)) do |space_id, _index_id, space_info|
          Protocol::Requests::Upsert.new(space_id:, tuple: tuple_for(tuple, space_info), operations:)
        end

        nil
      end

      def delete(space, key, index: 0, as: :tuple, timeout: nil)
        on_space(space, index, as:, timeout:) do |space_id, index_id|
          Protocol::Requests::Delete.new(space_id:, index_id:, key: key_tuple(key))
        end.first
      end

      # Deletes every tuple `select(space, key, index:, iterator:)` finds, which IPROTO DELETE can't do on a
      # non-unique index: selects batch_size tuples at a time, continuing past the last one with `after:`, and
      # deletes each by primary key. Returns the number of tuples deleted. TREE indexes only. Multikey and
      # functional indexes are not supported either: tuple-based `after` raises ServerError there, before
      # deleting anything.
      #
      # Outside a transaction it is not atomic: on failure the tuples deleted so far stay deleted, and the
      # raised Tarantool::Error carries the number confirmed deleted in #deleted (a lower bound). Tuples
      # inserted meanwhile behind the cursor are not deleted. Inside `transaction { |tx| tx.delete_by(...) }`
      # it is atomic (memtx needs memtx_use_mvcc_engine). `timeout:` bounds the whole operation; nil gives
      # each request request_timeout.
      def delete_by(space, key, index:, iterator: :eq, batch_size: 1000, timeout: nil)
        BatchDelete.new(self, space, key, index:, iterator:, batch_size:, timeout:).call
      end

      # on_push runs in the calling thread for each box.session.push message; an exception
      # raised by it abandons the call.
      def call(function_name, arguments = [], timeout: nil, on_push: nil)
        perform(Protocol::Requests::Call.new(function_name:, arguments:), timeout:, on_push:).data
      end

      def eval(expression, arguments = [], timeout: nil)
        perform(Protocol::Requests::Eval.new(expression:, arguments:), timeout:).data
      end

      def execute(sql, bindings = [], timeout: nil)
        statement = sql.is_a?(PreparedStatement) ? sql.id : sql

        SqlResult.from_response(perform(Protocol::Requests::Execute.new(statement:, bindings:), timeout:))
      end

      # A prepared statement belongs to the session, so a reconnect discards it.
      def prepare(sql, timeout: nil)
        response = perform(Protocol::Requests::Prepare.new(statement: sql), timeout:)

        PreparedStatement.new(response.body.fetch(Protocol::Constants::STMT_ID), method(:perform))
      end

      private

      # A retry after a schema change calls the block again, so the SpaceInfo kept is the one the response came from.
      def on_space(space, index, as:, timeout:, format: false)
        TupleShape.check(as)
        space_info = nil
        needs_format = format || as != :tuple
        response = perform_on_space(space, index, timeout:, format: needs_format) do |space_id, index_id, info|
          space_info = info
          yield space_id, index_id, info
        end

        response.data.map { |tuple| TupleShape.apply(as, tuple, space_info) }
      end

      def tuple_for(tuple, space_info) = tuple.is_a?(Hash) ? space_info.to_tuple(tuple) : tuple

      def key_tuple(key)
        key.is_a?(Array) ? key : [key]
      end
    end
  end
end
