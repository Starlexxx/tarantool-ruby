# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_EXECUTE: run SQL given as text or as a prepared statement id.
        # @api private
        Execute = Data.define(:statement, :bindings) do
          def type = Constants::EXECUTE

          def body
            key = statement.is_a?(Integer) ? Constants::STMT_ID : Constants::SQL_TEXT

            { key => statement, Constants::SQL_BIND => bindings }
          end
        end
      end
    end
  end
end
