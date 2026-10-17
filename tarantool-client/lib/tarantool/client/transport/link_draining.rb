# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Graceful shutdown of a Link's connection. Includers set @config and @state, and provide #emit.
      # @api private
      module LinkDraining
        # The server announced its shutdown and waits for this connection to close: new requests wait for the
        # next connection, in-flight ones finish, then the connection is closed and its loss handled as usual.
        def drain
          connection = @state.connection

          @state.start_draining(connection) do
            Thread.new { drain_connection(connection) }.tap do |thread|
              thread.name = "tarantool-drain #{@config.address}"
            end
          end
        end

        private

        # Without reconnect the drained connection becomes current again so requests fail with its reason.
        def drain_connection(connection)
          emit('shutdown.tarantool', pending: connection.in_flight)
          connection.wait_idle(@config.request_timeout)
          @state.finish_draining(connection) unless @config.reconnect
          connection.shut_down("server #{@config.address} is shutting down")
        rescue StandardError => e
          Diagnostics.warn(@config.logger, "drain failed for #{@config.address}: #{e.full_message}")
        end
      end
    end
  end
end
