# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_ROLLBACK: roll back the stream's transaction.
        Rollback = Data.define do
          def type = Constants::ROLLBACK
          def body = {}
        end
      end
    end
  end
end
