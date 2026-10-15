# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_PREPARE: prepare SQL text, or deallocate a prepared statement given its id.
        Prepare = Data.define(:statement) do
          def type = Constants::PREPARE
          def body = { (statement.is_a?(Integer) ? Constants::STMT_ID : Constants::SQL_TEXT) => statement }
        end
      end
    end
  end
end
