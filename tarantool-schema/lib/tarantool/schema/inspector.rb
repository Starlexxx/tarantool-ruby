# frozen_string_literal: true

module Tarantool
  module Schema
    # Reads one space from box.space. The name travels as an eval argument, never inside the Lua source.
    # @api private
    module Inspector
      LUA = <<~LUA
        local space = box.space[...]
        if space == nil then return nil end
        local indexes = {}
        for id, index in pairs(space.index) do
          if type(id) == 'number' then
            local parts = {}
            for _, part in ipairs(index.parts) do
              table.insert(parts, {fieldno = part.fieldno, type = part.type, is_nullable = part.is_nullable,
                                   path = part.path})
            end
            table.insert(indexes, {id = id, name = index.name, type = index.type, unique = index.unique,
                                   parts = parts, sequence = index.sequence_id ~= nil, func = index.func ~= nil})
          end
        end
        return {engine = space.engine, format = space:format(), indexes = indexes}
      LUA

      def self.call(client, name)
        raw = client.eval(LUA, [name.to_s]).first

        raw && LiveSpace.from_eval(raw)
      end
    end
  end
end
