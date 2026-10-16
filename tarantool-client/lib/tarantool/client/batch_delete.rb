# frozen_string_literal: true

module Tarantool
  class Client
    # Deletes every tuple a select over a TREE index finds: keyset pages via `after`, then one delete per tuple
    # by primary key. Drives only the public operations of its target, so it runs the same on Client and Stream.
    # @api private
    class BatchDelete
      def initialize(target, space, key, index:, iterator:, batch_size:, timeout:)
        @target = target
        @space = space
        @key = key
        @index = index
        @iterator = iterator
        @batch_size = batch_size
        @timeout = timeout
        @deleted = 0
      end

      def call
        fieldnos = primary_fieldnos
        cursor = nil

        loop do
          batch = fetch(cursor)
          delete_all(batch, fieldnos)
          return @deleted if batch.size < @batch_size

          cursor = batch.last
        end
      end

      private

      def primary_fieldnos
        @target.space_info(@space).primary_index.parts.map(&:fieldno)
      end

      def fetch(cursor)
        @target.select(@space, @key, index: @index, iterator: @iterator, limit: @batch_size, after: cursor)
      end

      def delete_all(batch, fieldnos)
        batch.each do |tuple|
          @deleted += 1 if @target.delete(@space, tuple.values_at(*fieldnos))
        end
      end
    end
  end
end
