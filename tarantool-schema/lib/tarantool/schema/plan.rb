# frozen_string_literal: true

module Tarantool
  module Schema
    # The live state of everything a definition declares, compared with it, and what is left to create.
    # @api private
    class Plan
      def initialize(spaces:, external:, client:)
        @comparisons = spaces.values.map { |space| compare(client, space.name, space.indexes, space) } +
                       external.map { |name, indexes| compare(client, name, indexes) }
      end

      # complete: anything still missing is a mismatch too, used after apply has created it.
      def verify(complete: false)
        by_space = @comparisons.to_h do |comparison|
          [comparison.name, comparison.mismatches + (complete ? still_missing(comparison) : [])]
        end
        by_space.reject! { |_, lines| lines.empty? }
        raise MismatchError, by_space if by_space.any?

        self
      end

      def creations
        @comparisons.flat_map do |comparison|
          space = comparison.missing_space? ? [Creation::Space.new(spec: comparison.space)] : []

          space + comparison.missing_indexes.map { |index| Creation::Index.new(space: comparison.name, spec: index) }
        end
      end

      private

      def compare(client, name, indexes, space = nil)
        Comparison.new(name:, indexes:, live: Inspector.call(client, name), space:)
      end

      def still_missing(comparison)
        return ['missing after apply'] if comparison.missing_space?

        comparison.missing_indexes.map { |index| "index #{index.name}: missing after apply" }
      end
    end
  end
end
