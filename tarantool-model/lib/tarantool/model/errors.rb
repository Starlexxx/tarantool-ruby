# frozen_string_literal: true

module Tarantool
  module Model
    class Error < Tarantool::Error; end

    # No row in the storage for this model's primary key.
    class RecordNotFound < Error
      attr_reader :model, :key

      def initialize(model, key)
        @model = model
        @key = key
        super("#{model.name} with key #{key.inspect} not found")
      end
    end

    # save! or create! on a record that fails validation.
    class RecordInvalid < Error
      attr_reader :record

      def initialize(record)
        @record = record
        super(record.errors.full_messages.join(', '))
      end
    end

    # A before callback threw :abort.
    class RecordNotSaved < Error
      attr_reader :record

      def initialize(record)
        @record = record
        super("#{record.class.name} was not saved: a before callback aborted")
      end
    end

    # The row's locking column changed since the record was loaded.
    class StaleObjectError < Error
      attr_reader :record, :attempted_action

      def initialize(record, attempted_action)
        @record = record
        @attempted_action = attempted_action
        super("Attempted to #{attempted_action} a stale #{record.class.name} with key #{record.to_key.inspect}")
      end
    end

    class RecordNotUnique < Error; end
    class SchemaMismatchError < Error; end
    class TransactionMismatchError < Error; end
    class NotSupportedError < Error; end
  end
end
