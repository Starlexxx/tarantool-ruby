# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      # @api private
      module Requests
        # IPROTO_PING: liveness check.
        # @api private
        Ping = Data.define do
          def type = Constants::PING
          def body = {}
        end
      end
    end
  end
end
