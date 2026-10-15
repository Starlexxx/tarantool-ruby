# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_BEGIN: open a transaction in a stream. The server rolls it back once the timeout (seconds) expires.
        Begin = Data.define(:isolation, :timeout) do
          def initialize(isolation:, **)
            unless Constants::ISOLATION_LEVELS.key?(isolation)
              raise ArgumentError, "unknown isolation level: #{isolation.inspect}"
            end

            super
          end

          def type = Constants::BEGIN_TRANSACTION

          # The server accepts only a MessagePack double for the timeout and rejects an integer.
          def body
            level = Constants::ISOLATION_LEVELS.fetch(isolation)

            { Constants::TXN_ISOLATION => level, Constants::TIMEOUT => timeout&.to_f }.compact
          end
        end
      end
    end
  end
end
