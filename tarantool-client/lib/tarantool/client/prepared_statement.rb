# frozen_string_literal: true

module Tarantool
  class Client
    # Server-side prepared SQL statement. Runs through the client or stream that prepared it.
    class PreparedStatement
      attr_reader :id

      def initialize(id, perform)
        @id = id
        @perform = perform
      end

      def execute(bindings = [], timeout: nil)
        SqlResult.from_response(@perform.call(Protocol::Requests::Execute.new(statement: id, bindings:), timeout:))
      end

      def close(timeout: nil)
        @perform.call(Protocol::Requests::Prepare.new(statement: id), timeout:)
        nil
      end
    end
  end
end
