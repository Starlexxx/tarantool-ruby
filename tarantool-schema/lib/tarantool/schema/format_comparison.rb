# frozen_string_literal: true

module Tarantool
  module Schema
    # Differences between a declared format and the live one, field by field in order. With add_field, declared
    # fields past the end of a matching live format are additions instead of a mismatch, as long as they are
    # nullable: Tarantool rejects a longer format otherwise while the space holds tuples.
    # @api private
    class FormatComparison
      ATTRIBUTES = %i[name type is_nullable].freeze

      def initialize(declared, live, add_field: false)
        @declared = declared
        @live = live
        @add_field = add_field
      end

      def mismatches
        fields = @declared.zip(@live).each_with_index.flat_map do |(declared, live), index|
          live ? field_mismatches(index + 1, declared, live) : []
        end

        count_mismatch(fields.empty?) + fields
      end

      # The declared fields to append, when that is allowed and the live format is a matching prefix.
      def additions
        return [] unless @add_field && mismatches.empty? && @live.size < @declared.size

        extra
      end

      private

      def extra = @declared.drop(@live.size)

      def count_mismatch(prefix_matches)
        return [] if @declared.size == @live.size
        return [] if prefix_matches && @add_field && @live.size < @declared.size && extra.all?(&:is_nullable)

        ["format: declared #{@declared.size} fields, actual #{@live.size}"] + addition_hints
      end

      def addition_hints
        return [] unless @add_field && @live.size < @declared.size

        extra.reject(&:is_nullable).map do |field|
          "field #{@declared.index(field) + 1} #{field.name}: must be is_nullable: true to be added"
        end
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
