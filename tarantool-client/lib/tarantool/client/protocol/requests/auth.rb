# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_AUTH: authenticate the session.
        Auth = Data.define(:user, :mechanism, :scramble) do
          def type = Constants::AUTH

          # Tarantool expects the scramble as MP_STR; binary Ruby strings would be packed as MP_BIN.
          def body
            {
              Constants::USER_NAME => user,
              Constants::TUPLE => [mechanism, scramble.dup.force_encoding(Encoding::UTF_8)]
            }
          end
        end
      end
    end
  end
end
