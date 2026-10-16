# frozen_string_literal: true

module Tarantool
  module Schema
    # Differences between one space as declared and as it is live. For a space declared elsewhere (only its
    # indexes are declared here) there is no spec: engine and format are not compared and index parts inherit
    # from the live format.
    # @api private
    class Comparison
      attr_reader :name, :space, :mismatches, :missing_indexes

      def initialize(name:, indexes:, live:, space: nil)
        @name = name
        @space = space
        @live = live
        @mismatches = []
        @missing_indexes = []
        live ? compare(indexes) : absent(indexes)
      end

      def missing_space? = @live.nil? && !@space.nil?

      private

      def absent(indexes)
        if @space
          @missing_indexes.concat(indexes)
        else
          @mismatches << 'missing'
        end
      end

      def compare(indexes)
        compare_space if @space
        indexes.each { |index| compare_index(index) }
      end

      def compare_space
        @mismatches << "engine: declared #{@space.engine}, actual #{@live.engine}" if @space.engine != @live.engine
        @mismatches.concat(FormatComparison.new(@space.format, @live.format).mismatches)
        compare_primary
      end

      def compare_primary
        declared = @space.indexes.first.name
        actual = @live.primary&.name
        @mismatches << "primary index: declared #{declared}, actual #{actual}" if actual && actual != declared
      end

      def compare_index(index)
        index = resolve(index) unless @space
        return unless index

        live = @live.index(index.name)
        return @missing_indexes << index unless live

        @mismatches.concat(IndexComparison.new(index, live).mismatches)
      end

      def resolve(index)
        fields = @live.fields
        unknown = index.unknown_fields(fields)
        return index.resolve(fields) if unknown.empty?

        @mismatches << "index #{index.name}: unknown field #{unknown.join(', ')}"

        nil
      end
    end
  end
end
