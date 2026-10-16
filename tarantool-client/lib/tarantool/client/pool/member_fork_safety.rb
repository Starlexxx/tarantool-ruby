# frozen_string_literal: true

module Tarantool
  class Client
    class Pool
      # Per-process reinit for forked children. Included in Member.
      module MemberForkSafety
        # Called by Pool#ensure_fork_safe before start_members re-runs Pool.new startup in the
        # child. Closes the inherited client (safe: only closes the child's fd copy, and joins
        # parent threads which are dead so they return immediately), then clears per-connection
        # state so start_members can connect fresh.
        def reset_for_fork
          old_retrier, old_client = @lock.synchronize do
            retrier = @retrier
            client = @client
            @retrier = nil
            @client = nil
            @read_only = nil
            [retrier, client]
          end
          old_retrier&.join
          old_client&.close
        end
      end
    end
  end
end
