# frozen_string_literal: true

module Tarantool
  class Client
    # Deletes every tuple a select over a TREE index finds: keyset pages via `after`, then one delete per tuple
    # by primary key. Drives only the public operations of its target, so it runs the same on Client and Stream.
    # @api private
    class BatchDelete
      def initialize(target, space, key, index:, iterator:, batch_size:, timeout:)
        validate_batch_size(batch_size)

        @target = target
        @space = space
        @key = key
        @index = index
        @iterator = iterator
        @batch_size = batch_size
        @timeout = timeout
        @deadline = Transport::Deadline.after(timeout)
        @deleted = 0
      end

      def call
        delete_pages(primary_fieldnos)
      rescue Error => e
        e.deleted = @deleted
        raise
      end

      private

      def validate_batch_size(batch_size)
        return if batch_size.is_a?(Integer) && batch_size.positive?

        raise ArgumentError, "batch_size must be a positive Integer, got #{batch_size.inspect}"
      end

      def delete_pages(fieldnos)
        cursor = nil

        loop do
          batch = fetch(cursor)
          delete_all(batch, fieldnos)
          return @deleted if batch.size < @batch_size

          cursor = batch.last
        end
      end

      def primary_fieldnos
        parts = @target.space_info(@space, timeout: remaining).primary_index.parts
        raise ArgumentError, 'delete_by cannot build a primary key from a JSON path part' if parts.any?(&:path)

        parts.map(&:fieldno)
      end

      def fetch(cursor)
        @target.select(@space, @key, index: @index, iterator: @iterator, limit: @batch_size, after: cursor,
                                     timeout: remaining)
      end

      def delete_all(batch, fieldnos)
        batch.each do |tuple|
          @deleted += 1 if @target.delete(@space, tuple.values_at(*fieldnos), timeout: remaining)
        end
      end

      # nil leaves each request on the connection's request_timeout.
      def remaining
        return unless @deadline

        left = Transport::Deadline.remaining(@deadline)
        raise TimeoutError, "delete_by did not finish within #{@timeout}s" if left.zero?

        left
      end
    end
  end
end
