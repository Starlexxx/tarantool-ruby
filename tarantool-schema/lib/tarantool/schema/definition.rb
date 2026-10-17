# frozen_string_literal: true

module Tarantool
  module Schema
    # Spaces and indexes an application needs. Built once from a block and frozen, so a definition kept in a
    # constant cannot grow when its file is loaded again. The block runs with the definition as self.
    class Definition
      def initialize(&block)
        @spaces = {}
        @external = {}
        instance_exec(&block) if block
        @spaces.transform_values! { |space| SpaceRules.check(space.resolve) }.freeze
        @external.each_value(&:freeze).freeze
        freeze
      end

      # Every user space as the server has it, or only the named ones. A space the DSL cannot express raises.
      def self.from_live(client, only: nil)
        arguments = SpaceLister.call(client, only:).to_h do |name|
          live = Inspector.call(client, name) || raise(ArgumentError, "space #{name}: not found")

          [name, LiveDefinition.arguments(name, live)]
        end

        new { arguments.each { |name, space| ensure_space(name, **space) } }
      end

      def ensure_space(name, format:, indexes:, engine: :memtx)
        raise ArgumentError, 'space without name' if name.nil?

        name = name.to_sym
        raise ArgumentError, "space #{name} is already declared" if @spaces.key?(name)
        raise ArgumentError, "space #{name}: declare it before its ensure_index" if @external.key?(name)

        @spaces[name] = SpaceSpec.build(name, engine:, format:, indexes:)
        nil
      end

      def ensure_index(space, name, **options)
        raise ArgumentError, 'space without name' if space.nil?

        space = space.to_sym
        index = IndexSpec.build(name, options)
        if @spaces.key?(space)
          @spaces[space] = @spaces[space].add_index(index)
        else
          add_external(space, index)
        end
        nil
      end

      def to_h = @spaces.transform_values(&:to_h)

      def plan(client) = build_plan(client).verify.creations.map(&:to_s)

      # The second plan re-reads everything, so a space another deploy created differently in the meantime fails
      # here instead of being reported as created.
      def apply(client)
        creations = build_plan(client).verify.creations
        creations.each { |creation| creation.apply(client) }
        build_plan(client).verify(complete: true)

        creations.map(&:to_s)
      end

      private

      def build_plan(client) = Plan.new(spaces: @spaces, external: @external, client:)

      # A space declared elsewhere already has its primary key, so an index added here never gets a sequence.
      def add_external(space, index)
        if index.sequence
          raise ArgumentError, "index #{index.name}: sequence is only allowed on the primary index, declare it " \
                               'with ensure_space'
        end
        indexes = @external.fetch(space, [])
        if indexes.any? { |i| i.name == index.name }
          raise ArgumentError, "space #{space}: duplicate index #{index.name}"
        end

        @external[space] = [*indexes, index]
      end
    end
  end
end
