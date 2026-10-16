# frozen_string_literal: true

module Tarantool
  module Schema
    # Base class for errors raised by tarantool-schema.
    class Error < Tarantool::Error; end

    # The live schema differs from the declaration. Raised before apply creates anything.
    class MismatchError < Error
      attr_reader :mismatches

      def initialize(by_space)
        @mismatches = by_space.flat_map { |space, lines| lines.map { |line| "space #{space}: #{line}" } }
        super(describe(by_space))
      end

      private

      def describe(by_space)
        sections = by_space.map do |space, lines|
          ["  space #{space}:", *lines.map { |line| "    #{line}" }].join("\n")
        end

        "schema mismatch:\n#{sections.join("\n")}"
      end
    end
  end
end
