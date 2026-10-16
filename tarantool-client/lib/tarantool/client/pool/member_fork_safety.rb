# frozen_string_literal: true

module Tarantool
  class Client
    class Pool
      # @api private
      module MemberForkSafety
        # Pool re-runs its startup in a forked child after this. The inherited client and retry thread belong
        # to the parent: closing the client in the child only drops its socket copy, dead threads join at once.
        # Nothing inherited may stop the reset, or the child's pool would never start its members.
        def reset_for_fork
          old_retrier, old_client = clear_fork_state
          ThreadJoin.join(old_retrier)
          close_inherited(old_client)
          @instrumentation&.notify('fork.tarantool')
        end

        private

        def clear_fork_state
          @lock.synchronize do
            retrier = @retrier
            client = @client
            @retrier = nil
            @client = nil
            @read_only = nil
            [retrier, client]
          end
        end

        def close_inherited(client)
          client&.close
        rescue StandardError
          nil
        end
      end
    end
  end
end
