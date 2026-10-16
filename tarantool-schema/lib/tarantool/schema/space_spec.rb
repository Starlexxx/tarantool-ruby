# frozen_string_literal: true

module Tarantool
  module Schema
    # A declared space. Its index parts get the field types and nullability once #resolve runs.
    SpaceSpec = Data.define(:name, :engine, :format, :indexes) do
      def self.build(name, engine:, format:, indexes:)
        raise ArgumentError, 'space without name' if name.nil?

        context = "space #{name}"
        space = new(name: name.to_sym, engine: build_engine(engine, context), format: build_format(format, context),
                    indexes: [].freeze)

        build_indexes(space, indexes, context)
      end

      def self.build_engine(engine, context)
        engine = engine.to_s
        raise ArgumentError, "#{context}: unknown engine #{engine.inspect}" unless SpaceSpec::ENGINES.include?(engine)

        -engine
      end

      def self.build_indexes(space, indexes, context)
        raise ArgumentError, "#{context}: indexes must be an Array" unless indexes.is_a?(Array)

        indexes.reduce(space) { |result, raw| result.add_index(IndexSpec.build(*index_arguments(raw, context))) }
      end

      def self.build_format(raw, context)
        raise ArgumentError, "#{context}: format must be an Array" unless raw.is_a?(Array)

        fields = raw.map { |field| FieldSpec.build(field) }
        duplicates = fields.map(&:name).tally.select { |_, count| count > 1 }.keys
        raise ArgumentError, "#{context}: duplicate field #{duplicates.join(', ')}" if duplicates.any?

        fields.freeze
      end

      def self.index_arguments(raw, context)
        raise ArgumentError, "#{context}: index must be a Hash, got #{raw.inspect}" unless raw.is_a?(Hash)

        [raw.fetch(:name) { raise ArgumentError, "#{context}: index without name" }, raw.except(:name)]
      end
      private_class_method :build_engine, :build_indexes, :build_format, :index_arguments

      def add_index(index)
        raise ArgumentError, "space #{name}: duplicate index #{index.name}" if indexes.any? { |i| i.name == index.name }

        with(indexes: [*indexes, index].freeze)
      end

      def resolve
        fields = format.to_h { |field| [field.name, field] }
        unknown = unknown_field_errors(fields)
        raise ArgumentError, "space #{name}: #{unknown.join('; ')}" if unknown.any?

        with(indexes: indexes.map { |index| index.resolve(fields) }.freeze)
      end

      def to_h = { engine:, format: format.map(&:to_h), indexes: indexes.map(&:to_h) }

      def to_lua = { 'engine' => engine, 'format' => format.map(&:to_lua) }

      private

      def unknown_field_errors(fields)
        indexes.flat_map do |index|
          index.unknown_fields(fields).map { |field| "index #{index.name}: unknown field #{field}" }
        end
      end
    end

    SpaceSpec::ENGINES = %w[memtx vinyl].freeze
  end
end
