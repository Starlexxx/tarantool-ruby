# frozen_string_literal: true

module Tarantool
  module Schema
    # Privileges one user or role must have on one space.
    # @api private
    GrantSpec = Data.define(:user, :privileges, :space) do
      def self.build(user, privileges, on:)
        raise ArgumentError, 'grant without user' if user.nil?
        raise ArgumentError, "grant #{user} without space" if on.nil?

        user = user.to_sym
        space = on.to_sym

        new(user:, privileges: Privileges.check(privileges, "grant #{user} on #{space}").freeze, space:)
      end

      # The grant that would complete a live mask, or nil when it already covers the declaration.
      def missing(mask)
        lacking = privileges - Privileges.names(mask)

        lacking.empty? ? nil : with(privileges: lacking.freeze)
      end

      def to_s = "grant #{user} #{privileges.join(',')} on #{space}"
    end
  end
end
