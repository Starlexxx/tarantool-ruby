# frozen_string_literal: true

module Tarantool
  module Model
    # Optimistic locking on the attribute named by locking_column, when the model declares it. An update compares
    # the stored version with the record's and bumps it, inside a transaction on storages that have them, so a
    # concurrent commit on the same row surfaces as StaleObjectError instead of being overwritten.
    module Locking
      extend ActiveSupport::Concern

      ER_TRANSACTION_CONFLICT = 97
      private_constant :ER_TRANSACTION_CONFLICT

      included do
        class_attribute :locking_column, instance_accessor: false, default: :lock_version
      end

      class_methods do
        def locking_enabled?
          !locking_column.nil? && attribute_names.include?(locking_column.to_s)
        end
      end

      private

      def create_row
        public_send("#{locking_column}=", 0) if locking_enabled? && public_send(locking_column).nil?

        super
      end

      def update_pending?
        return super unless locking_enabled?

        changes.except(locking_column.to_s).any?
      end

      def updated_row
        return super unless locking_enabled?

        atomically(:update) do
          locked_row(:update) || raise(RecordNotFound.new(self.class, key_in_database))

          write_row(locked_operations)
        end
      end

      def locked_operations
        column = locking_column.to_s
        operations = update_operations.reject { |(_operator, name, _value)| name == column }

        operations << ['=', column, public_send(locking_column) + 1]
      end

      # The row, or nil when it is gone; a version other than the record's raises.
      def locked_row(action)
        row = space_storage.get(space_name, key_in_database)
        raise StaleObjectError.new(self, action) if row && row.attributes[locking_column] != public_send(locking_column)

        row
      end

      # Inside an open Model.transaction the check joins it; without transactions (crud) it runs unguarded.
      def atomically(action, &)
        storage = writing_storage
        return yield if Transactions.handle(storage) || !storage.supports_transactions?

        storage.transaction(&)
      rescue Tarantool::ServerError => e
        raise StaleObjectError.new(self, action) if e.code == ER_TRANSACTION_CONFLICT

        raise
      end

      def locking_column = self.class.locking_column

      def locking_enabled? = self.class.locking_enabled?
    end
  end
end
