# frozen_string_literal: true

module Tarantool
  class Client
    # Clients with a transaction open in the current fiber. Thread#[] is fiber-local and, unlike
    # Fiber storage, not inherited, so a thread or fiber spawned inside a transaction block may
    # open its own transaction.
    module TransactionScope
      NESTED = 'nested transactions are not supported'

      module_function

      def enter(client)
        open = Thread.current[:tarantool_transactions] ||= {}
        raise TransactionError, NESTED if open.key?(client)

        open[client] = true

        begin
          yield
        ensure
          open.delete(client)
        end
      end
    end
  end
end
