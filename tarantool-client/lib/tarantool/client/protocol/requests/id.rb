# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_ID: exchange protocol version and feature lists.
        Id = Data.define(:version, :features) do
          def type = Constants::ID
          def body = { Constants::VERSION => version, Constants::FEATURES => features }
        end
      end
    end
  end
end
