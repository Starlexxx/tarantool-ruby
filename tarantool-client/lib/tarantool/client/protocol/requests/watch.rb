# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_WATCH: subscribe to a key, or acknowledge the last event for it. No reply.
        # @api private
        Watch = Data.define(:key) do
          def type = Constants::WATCH
          def body = { Constants::EVENT_KEY => key }
        end
      end
    end
  end
end
