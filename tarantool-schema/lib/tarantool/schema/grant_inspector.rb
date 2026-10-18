# frozen_string_literal: true

module Tarantool
  module Schema
    # Privilege masks on one space by grantee name, and which of the declared grantees do not exist. A grantee
    # may be a user or a role. Reads _priv and _user, so the connection needs read on both.
    # @api private
    LiveGrants = Data.define(:masks, :missing)

    # @api private
    module GrantInspector
      LUA = <<~LUA
        local name, grantees = ...
        local masks = setmetatable({}, {__serialize = 'map'})
        local space = box.space[name]
        if space ~= nil then
          for _, row in box.space._priv.index.object:pairs({'space', space.id}) do
            local grantee = box.space._user:get(row[2])
            if grantee ~= nil then masks[grantee.name] = row[5] end
          end
        end
        local missing = setmetatable({}, {__serialize = 'seq'})
        for _, grantee in ipairs(grantees) do
          if not (box.schema.user.exists(grantee) or box.schema.role.exists(grantee)) then
            table.insert(missing, grantee)
          end
        end
        return {masks = masks, missing = missing}
      LUA

      def self.call(client, space, grantees)
        raw = client.eval(LUA, [space.to_s, grantees.map(&:to_s)]).first

        LiveGrants.new(masks: raw.fetch('masks'), missing: raw.fetch('missing'))
      end
    end
  end
end
