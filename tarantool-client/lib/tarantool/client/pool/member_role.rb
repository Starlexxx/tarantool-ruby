# frozen_string_literal: true

module Tarantool
  class Client
    class Pool
      # The role a member's instance reports through box.status. Includers set @lock, @changed, @read_only
      # and @instrumentation.
      # @api private
      module MemberRole
        private

        def update(status)
          read_only = status['is_ro']
          changed = @lock.synchronize do
            @read_only = read_only
            @changed.broadcast
            role_changed?(read_only)
          end

          @instrumentation&.notify('role_change.tarantool', read_only:) if changed
        end

        # Compared against the last known role rather than @read_only, which disconnect and fork reset:
        # a reconnect that brings back the same role is not a change. A status without is_ro is routing
        # information only, never a role to compare against.
        def role_changed?(read_only)
          return false if read_only.nil?

          previous = @known_read_only
          @known_read_only = read_only
          !previous.nil? && previous != read_only
        end
      end
    end
  end
end
