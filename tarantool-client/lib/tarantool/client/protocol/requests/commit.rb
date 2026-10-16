# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_COMMIT: commit the stream's transaction.
        # @api private
        Commit = Data.define do
          def type = Constants::COMMIT
          def body = {}
        end
      end
    end
  end
end
