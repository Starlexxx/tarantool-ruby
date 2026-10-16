# frozen_string_literal: true

module Tarantool
  class Client
    class Pool
      # Per-process reinit for forked children. Included in Member.
      # @api private
      module MemberForkSafety
        # Pool re-runs its startup in a forked child after this. The inherited client and retry thread belong
        # to the parent: closing the client in the child only drops its socket copy, dead threads join at once.
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
