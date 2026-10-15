# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_PING: liveness check.
        Ping = Data.define do
          def type = Constants::PING
          def body = {}
        end
      end
    end
  end
end
