# frozen_string_literal: true

module Tarantool
  class Client
    # Data operations, call and eval. Includers implement
    # `perform(request, timeout:)` and `resolve(space, index)`.
    module Operations
      def ping(timeout: nil) # rubocop:disable Naming/PredicateMethod
        perform(Protocol::Requests::Ping.new, timeout:)
        true
      end

      def select(space, key = [], index: 0, limit: Protocol::Constants::MAX_LIMIT, offset: 0, iterator: :eq,
                 timeout: nil)
        space_id, index_id = resolve(space, index)
        request = Protocol::Requests::Select.new(space_id:, index_id:, key: Array(key), limit:, offset:, iterator:)
        perform(request, timeout:).data
      end

      def insert(space, tuple, timeout: nil)
        space_id, = resolve(space, 0)
        perform(Protocol::Requests::Insert.new(space_id:, tuple:), timeout:).data.first
      end

      def replace(space, tuple, timeout: nil)
        space_id, = resolve(space, 0)
        perform(Protocol::Requests::Replace.new(space_id:, tuple:), timeout:).data.first
      end

      def update(space, key, operations, index: 0, timeout: nil)
        space_id, index_id = resolve(space, index)
        request = Protocol::Requests::Update.new(space_id:, index_id:, key: Array(key), operations:)
        perform(request, timeout:).data.first
      end

      def upsert(space, tuple, operations, timeout: nil)
        space_id, = resolve(space, 0)
        perform(Protocol::Requests::Upsert.new(space_id:, tuple:, operations:), timeout:)
        nil
      end

      def delete(space, key, index: 0, timeout: nil)
        space_id, index_id = resolve(space, index)
        perform(Protocol::Requests::Delete.new(space_id:, index_id:, key: Array(key)), timeout:).data.first
      end

      def call(function_name, arguments = [], timeout: nil)
        perform(Protocol::Requests::Call.new(function_name:, arguments:), timeout:).data
      end

      def eval(expression, arguments = [], timeout: nil)
        perform(Protocol::Requests::Eval.new(expression:, arguments:), timeout:).data
      end
    end
  end
end
