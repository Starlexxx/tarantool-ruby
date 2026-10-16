# frozen_string_literal: true

module Tarantool
  module Schema
    # Rules Tarantool enforces on a whole space, checked on a resolved SpaceSpec before anything reaches the
    # server.
    class SpaceRules
      SEQUENCE_TYPES = %w[unsigned integer].freeze

      def self.check(space) = new(space).check

      def initialize(space)
        @space = space
      end

      def check
        raise error('at least one index is required') if @space.indexes.empty?

        check_primary(@space.indexes.first)
        check_no_secondary_sequence
        check_engine
        @space.indexes.each { |index| KeyRules.check(index, "space #{@space.name}") }

        @space
      end

      private

      def check_no_secondary_sequence
        extra = @space.indexes.drop(1).find(&:sequence)
        return unless extra

        raise error("index #{extra.name}: sequence is only allowed on the primary index")
      end

      def check_primary(index)
        check_primary_type(index)
        check_primary_unique(index)
        check_primary_nullable(index)
        check_sequence(index) if index.sequence
      end

      def check_primary_type(index)
        return unless IndexSpec::NON_UNIQUE.include?(index.type)

        raise error("primary index #{index.name} can not be #{index.type}")
      end

      def check_primary_unique(index)
        raise error("primary index #{index.name} must be unique") unless index.unique
      end

      def check_primary_nullable(index)
        nullable = index.parts.find(&:is_nullable)
        raise error("primary index #{index.name}: part #{nullable.field} can not be nullable") if nullable
      end

      def check_sequence(index)
        return if index.parts.size == 1 && SEQUENCE_TYPES.include?(index.parts.first.type)

        raise error("index #{index.name}: sequence needs a single unsigned or integer part")
      end

      def check_engine
        return if @space.engine == 'memtx'

        other = @space.indexes.reject { |index| index.type == 'tree' }
        raise error("vinyl supports only tree indexes, got #{other.map(&:name).join(', ')}") if other.any?
      end

      def error(message) = ArgumentError.new("space #{@space.name}: #{message}")
    end
  end
end
