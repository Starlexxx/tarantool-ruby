# frozen_string_literal: true

module Tarantool
  module Schema
    # A declared index with create_index defaults filled in. Rules that depend on the space (primary key,
    # engine, sequence) live in SpaceRules.
    IndexSpec = Data.define(:name, :type, :unique, :parts, :sequence) do
      def self.build(name, raw)
        raise ArgumentError, 'index without name' if name.nil?

        context = "index #{name}"
        Options.check(raw, %i[parts unique type sequence], context)
        index = new(name: name.to_sym, type: type(raw, context), parts: parts(raw[:parts], context),
                    unique: Options.boolean(raw.fetch(:unique, true), "#{context} unique"),
                    sequence: Options.boolean(raw.fetch(:sequence, false), "#{context} sequence"))
        check_unique(index, context)

        index
      end

      def self.type(raw, context)
        type = raw.fetch(:type, :tree).to_s
        raise ArgumentError, "#{context}: unknown type #{type.inspect}" unless IndexSpec::TYPES.include?(type)

        type
      end

      def self.parts(raw, context)
        raise ArgumentError, "#{context}: parts must be a non-empty Array" unless raw.is_a?(Array) && raw.any?

        raw.map { |part| PartSpec.build(part) }.freeze
      end

      def self.check_unique(index, context)
        return unless index.unique && IndexSpec::NON_UNIQUE.include?(index.type)

        raise ArgumentError, "#{context}: #{index.type} index can not be unique, set unique: false"
      end
      private_class_method :type, :parts, :check_unique

      def unknown_fields(fields) = parts.map(&:field).reject { |field| fields.key?(field) }

      def resolve(fields) = with(parts: parts.map { |part| part.inherit(fields.fetch(part.field)) }.freeze)

      def to_h = super.merge(parts: parts.map(&:to_h))

      def to_lua = { 'type' => type, 'unique' => unique, 'parts' => parts.map(&:to_lua), 'sequence' => sequence }
    end

    IndexSpec::TYPES = %w[tree hash bitset rtree].freeze
    IndexSpec::NON_UNIQUE = %w[bitset rtree].freeze
  end
end
