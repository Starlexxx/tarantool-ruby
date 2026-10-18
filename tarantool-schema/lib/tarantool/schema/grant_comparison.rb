# frozen_string_literal: true

module Tarantool
  module Schema
    # Declared grants on one space against the live ones: what is still to grant, and grantees that do not
    # exist. Privileges granted but not declared are ignored, nothing is ever revoked. For a space that does not
    # exist yet the live masks are empty, so everything is to grant, and a missing grantee is still a mismatch.
    # @api private
    class GrantComparison
      attr_reader :mismatches, :missing

      def initialize(grants, live)
        @mismatches = []
        @missing = []
        grants.each { |grant| compare(grant, live) }
      end

      private

      def compare(grant, live)
        return @mismatches << "grant #{grant.user}: no such user or role" if live.missing.include?(grant.user.to_s)

        lacking = grant.missing(live.masks.fetch(grant.user.to_s, 0))

        @missing << lacking if lacking
      end
    end
  end
end
