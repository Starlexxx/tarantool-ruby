# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      # In-memory storage for application tests, without a Tarantool server. Spaces are declared in
      # tarantool-schema's ensure_space shape. `behaves_like: :box` keeps the Storage::Box contract, `:crud` the
      # Storage::Crud one: what the server would reject is raised with the classes and codes the application sees
      # in production. The README lists what it does not model.
      class MemoryStorage
        MODES = { box: BoxMode }.freeze

        def self.from_definition(definition, **)
          new(definition.to_h, **)
        end

        def initialize(spaces, behaves_like: :box)
          @mode = MODES.fetch(behaves_like) do
            raise ArgumentError, "behaves_like must be one of #{MODES.keys.join(', ')}, got #{behaves_like.inspect}"
          end.new
          @spaces = spaces.to_h { |name, schema| [name.to_s, build_space(name, schema)] }
        end

        def verify(space, attributes:, primary_key:)
          perform(space, :get) { |table| @mode.verify(table, attributes:, primary_key:) }
        end

        private

        def perform(space, operation)
          yield @spaces.fetch(space.to_s) { raise Violation.unknown_space(space) }
        rescue Violation => e
          raise @mode.error(e, operation)
        end

        def build_space(name, schema)
          declaration = Declaration.new(name, schema)

          Space.new(declaration.space_info, sequence: declaration.sequence && @mode.sequences?)
        end
      end
    end
  end
end
