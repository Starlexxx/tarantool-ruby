# frozen_string_literal: true

module Tarantool
  module Schema
    # The live state of everything a definition declares, compared with it, and what is left to create.
    # @api private
    class Plan
      def initialize(spaces:, external:, client:, alter: [], grants: {})
        @alter = alter
        @grants = grants
        @comparisons = spaces.values.map { |space| compare(client, space.name, space.indexes, space) } +
                       external.map { |name, indexes| compare(client, name, indexes) } +
                       granted_only(spaces, external).map { |name| compare(client, name, []) }
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

      # Per space: the space itself or its format change, then its indexes, so an index on a new field works,
      # then its grants.
      def creations
        @comparisons.flat_map do |comparison|
          space_creation(comparison) +
            comparison.missing_indexes.map { |index| Creation::Index.new(space: comparison.name, spec: index) } +
            comparison.missing_grants.map { |grant| Creation::Grant.new(spec: grant) }
        end
      end

      private

      def granted_only(spaces, external) = @grants.keys - spaces.keys - external.keys

      def space_creation(comparison)
        return [Creation::Space.new(spec: comparison.space)] if comparison.missing_space?
        return [] if comparison.format_additions.empty?

        [Creation::Format.new(space: comparison.space, fields: comparison.format_additions)]
      end

      def compare(client, name, indexes, space = nil)
        grants = @grants.fetch(name, [])
        live_grants = GrantInspector.call(client, name, grants.map(&:user)) if grants.any?

        Comparison.new(name:, indexes:, live: Inspector.call(client, name), space:, alter: @alter, grants:,
                       live_grants:)
      end

      def still_missing(comparison)
        return ['missing after apply'] if comparison.missing_space?

        format = comparison.format_additions.empty? ? [] : ['format: fields missing after apply']

        format + comparison.missing_indexes.map { |index| "index #{index.name}: missing after apply" } +
          comparison.missing_grants.map { |grant| "grant #{grant.user}: missing after apply" }
      end
    end
  end
end
