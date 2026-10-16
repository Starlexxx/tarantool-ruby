# frozen_string_literal: true

module Tarantool
  module Schema
    # Differences between a declared index, its parts resolved, and the live index of the same name.
    # @api private
    class IndexComparison
      ATTRIBUTES = %i[type unique sequence].freeze

      def initialize(declared, live)
        @declared = declared
        @live = live
      end

      def mismatches
        ATTRIBUTES.filter_map { |attribute| attribute_mismatch(attribute) } + parts_mismatch
      end

      private

      def attribute_mismatch(attribute)
        expected = @declared.public_send(attribute)
        actual = @live.public_send(attribute)

        "index #{@declared.name}: #{attribute} declared #{expected}, actual #{actual}" if expected != actual
      end

      def parts_mismatch
        return [] if @declared.parts == @live.parts

        ["index #{@declared.name}: parts declared #{describe(@declared.parts)}, actual #{describe(@live.parts)}"]
      end

      def describe(parts)
        parts.map { |part| [part.field, part.path, part.type, ('nullable' if part.is_nullable)].compact.join(' ') }
             .join(', ')
      end
    end
  end
end
