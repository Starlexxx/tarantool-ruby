# frozen_string_literal: true

module Tarantool
  class Client
    class Pool
      # The role a member's instance reports through box.status. Includers set @lock, @changed, @read_only and
      # @instrumentation.
      # @api private
      module MemberRole
        private

        def update(status)
          read_only = status['is_ro']
          changed = @lock.synchronize do
            previous = @read_only
            @read_only = read_only
            @changed.broadcast
            previous != read_only
          end

          @instrumentation&.notify('role_change.tarantool', read_only:) if changed
        end
      end
    end
  end
end
