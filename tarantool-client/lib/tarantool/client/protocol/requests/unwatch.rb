# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_UNWATCH: drop the subscription to a key. No reply.
        Unwatch = Data.define(:key) do
          def type = Constants::UNWATCH
          def body = { Constants::EVENT_KEY => key }
        end
      end
    end
  end
end
