# frozen_string_literal: true

module Tarantool
  module Schema
    # What apply creates. Names and options are eval arguments, never part of the Lua source. if_not_exists keeps
    # a deploy racing another one from failing; the re-verification after apply catches what the other one made.
    # @api private
    module Creation
      SPACE_LUA = <<~LUA
        local name, options = ...
        box.schema.space.create(name, options)
      LUA

      INDEX_LUA = <<~LUA
        local space, name, options = ...
        box.space[space]:create_index(name, options)
      LUA

      FORMAT_LUA = <<~LUA
        local name, format = ...
        box.space[name]:format(format)
      LUA

      Space = Data.define(:spec) do
        def apply(client)
          client.eval(SPACE_LUA, [spec.name.to_s, spec.to_lua.merge('if_not_exists' => true)])
        end

        def to_s = "space #{spec.name}"
      end

      # The whole declared format goes out: the live one is a prefix of it, verified before apply.
      Format = Data.define(:space, :fields) do
        def apply(client)
          client.eval(FORMAT_LUA, [space.name.to_s, space.format.map(&:to_lua)])
        end

        def to_s = "format #{space.name}: add #{fields.map(&:name).join(', ')}"
      end

      Index = Data.define(:space, :spec) do
        def apply(client)
          client.eval(INDEX_LUA, [space.to_s, spec.name.to_s, spec.to_lua.merge('if_not_exists' => true)])
        end

        def to_s = "index #{space}.#{spec.name}"
      end
    end
  end
end
