# frozen_string_literal: true

module Tarantool
  module Crud
    # Iterates a select batch by batch, continuing after the last tuple until a short batch arrives.
    class Scan
      def initialize(space, conditions, batch_size:, options:)
        raise ArgumentError, 'batch_size must be positive' unless batch_size.positive?

        @space = space
        @conditions = conditions
        @batch_size = batch_size
        @options = options
      end

      def each(&block)
        return to_enum(:each) unless block_given?

        options = @options.merge(first: @batch_size)
        loop do
          batch = @space.select(@conditions, **options)
          batch.each(&block)
          break if batch.size < @batch_size

          options = options.merge(after: batch.tuples.last)
        end
      end
    end
  end
end
