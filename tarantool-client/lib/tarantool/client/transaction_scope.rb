# frozen_string_literal: true

module Tarantool
  class Client
    # Clients with a transaction open in the current fiber.
    module TransactionScope
      NESTED = 'nested transactions are not supported'
    end
  end
end
