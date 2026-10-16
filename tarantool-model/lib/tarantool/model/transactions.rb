# frozen_string_literal: true

module Tarantool
  module Model
    # Open transactions of the current fiber, keyed by storage instance (Thread#[] is fiber-local). A model
    # whose storage has no open transaction would write outside the one that is open, and commit on its own.
    module Transactions
      KEY = :tarantool_model_transactions
      MISMATCH = 'a write through another storage inside a transaction would commit outside it; ' \
                 'models in one transaction must share one storage instance'

      module_function

      def open(storage, handle)
        registry = current
        registry[storage] = handle

        yield
      ensure
        registry&.delete(storage)
      end

      def handle(storage)
        current[storage]
      end

      def check_write!(storage)
        registry = current
        return if registry.empty? || registry.key?(storage)

        raise TransactionMismatchError, MISMATCH
      end

      def current
        Thread.current[KEY] ||= {}.compare_by_identity
      end
    end
  end
end
