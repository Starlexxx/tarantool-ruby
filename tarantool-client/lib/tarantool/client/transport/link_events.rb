# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Lifecycle events and hooks of a Link. Includers set @config, @state and @instrumentation, and provide
      # #install.
      # @api private
      module LinkEvents
        private

        # A failing hook is the caller's bug, not a reason to stop reconnecting or to drop the new connection.
        def run_hook(name)
          yield
        rescue StandardError => e
          Diagnostics.warn(@config.logger, "#{name} failed for #{@config.address}: #{e.full_message}")
        end

        # Without reconnect the link keeps the lost connection, so the loss of the current one is all to
        # report. The reader thread's disconnect handler and install's own loss check can both reach this
        # for the same connection, so LinkState claims the loss once.
        def report_lost(connection)
          emit('disconnect.tarantool', reason: connection.failure&.message) if @state.claim_loss(connection)
        end

        # A connection the link was closed under, or that broke during on_ready, is no reconnect to report.
        def reconnected(connection, attempts)
          run_hook('on_ready') { install(connection) }
          emit('reconnect.tarantool', attempts:) unless connection.closed?
        end

        def give_up(attempts, error)
          message = "cannot reconnect to #{@config.address} after #{attempts} attempts: #{error.message}"

          fail_reconnect(ConnectionError.new(message), attempts:)
        end

        def fail_reconnect(error, **payload)
          @state.give_up(error)
          emit('reconnect_failed.tarantool', **payload, **Instrumentation.exception_keys(error))
        end

        # Link already has a public #notify for WATCH/UNWATCH requests, so events use a different name.
        def emit(name, **payload) = @instrumentation&.notify(name, payload)
      end
    end
  end
end
