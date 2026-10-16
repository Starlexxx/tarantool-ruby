# frozen_string_literal: true

module Tarantool
  module Schema
    # Differences between a declared format and the live one, field by field in order.
    class FormatComparison
      ATTRIBUTES = %i[name type is_nullable].freeze

      def initialize(declared, live)
        @declared = declared
        @live = live
      end

      def mismatches
        fields = @declared.zip(@live).each_with_index.flat_map do |(declared, live), index|
          live ? field_mismatches(index + 1, declared, live) : []
        end

        count_mismatch + fields
      end

      private

      def count_mismatch
        return [] if @declared.size == @live.size

        ["format: declared #{@declared.size} fields, actual #{@live.size}"]
      end

      def field_mismatches(number, declared, live)
        ATTRIBUTES.filter_map do |attribute|
          expected = declared.public_send(attribute)
          actual = live.public_send(attribute)
          "field #{number} #{declared.name}: #{attribute} declared #{expected}, actual #{actual}" if expected != actual
        end
      end
    end
  end
end
