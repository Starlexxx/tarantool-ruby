# frozen_string_literal: true

module Tarantool
  class Client
    # Data operations, call, eval and SQL. Includers implement `perform(request, timeout:, on_push: nil)`
    # and `perform_on_space(space, index, timeout:) { |space_id, index_id| request }`,
    # which returns the response to the request built by the block.
    module Operations
      def ping(timeout: nil)
        perform(Protocol::Requests::Ping.new, timeout:)
        true
      end

      def select(space, key = [], index: 0, limit: Protocol::Constants::MAX_LIMIT, offset: 0, iterator: :eq,
                 timeout: nil)
        perform_on_space(space, index, timeout:) do |space_id, index_id|
          Protocol::Requests::Select.new(space_id:, index_id:, key: key_tuple(key), limit:, offset:, iterator:)
        end.data
      end

      def insert(space, tuple, timeout: nil)
        perform_on_space(space, 0, timeout:) do |space_id|
          Protocol::Requests::Insert.new(space_id:, tuple:)
        end.data.first
      end

      def replace(space, tuple, timeout: nil)
        perform_on_space(space, 0, timeout:) do |space_id|
          Protocol::Requests::Replace.new(space_id:, tuple:)
        end.data.first
      end

      def update(space, key, operations, index: 0, timeout: nil)
        perform_on_space(space, index, timeout:) do |space_id, index_id|
          Protocol::Requests::Update.new(space_id:, index_id:, key: key_tuple(key), operations:)
        end.data.first
      end

      def upsert(space, tuple, operations, timeout: nil)
        perform_on_space(space, 0, timeout:) do |space_id|
          Protocol::Requests::Upsert.new(space_id:, tuple:, operations:)
        end
        nil
      end

      def delete(space, key, index: 0, timeout: nil)
        perform_on_space(space, index, timeout:) do |space_id, index_id|
          Protocol::Requests::Delete.new(space_id:, index_id:, key: key_tuple(key))
        end.data.first
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

      def key_tuple(key)
        key.is_a?(Array) ? key : [key]
      end
    end
  end
end
