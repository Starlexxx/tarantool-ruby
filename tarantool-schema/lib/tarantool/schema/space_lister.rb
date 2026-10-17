# frozen_string_literal: true

module Tarantool
  module Schema
    # Names of the spaces an application owns: ids past the system range, names without a leading underscore
    # (vshard's _bucket, crud's _ddl_* stay out). An explicit list skips the server.
    # @api private
    module SpaceLister
      LUA = <<~LUA
        local names = {}
        for _, space in box.space._space:pairs(box.schema.SYSTEM_ID_MAX + 1, {iterator = 'GE'}) do
          if not space.name:match('^_') then table.insert(names, space.name) end
        end
        return names
      LUA

      def self.call(client, only: nil)
        return only.map(&:to_sym) if only

        Array(client.eval(LUA).first).map(&:to_sym)
      end
    end
  end
end
