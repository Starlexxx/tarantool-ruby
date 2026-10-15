# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Keeps one instance connected. Owns the current Connection; once it is lost, a background thread
      # opens new ones with backoff while requests wait for one to become ready.
      # States: connecting -> ready -> reconnecting -> closed.
      class Link
        attr_writer :event_handler

        # on_connect runs on each new connection before requests can use it and may raise to fail the
        # attempt; on_ready runs once the connection is current.
        def initialize(config, on_connect:, on_ready:, backoff: nil)
          @config = config
          @on_connect = on_connect
          @on_ready = on_ready
          @backoff = backoff || Backoff.new(base: config.reconnect_delay, max: config.reconnect_max_delay)
          @state = LinkState.new(config.address, reconnect: config.reconnect)
        end

        def connect
          install(open_connection)
          self
        end

        def perform(request, timeout:, **)
          deadline = Deadline.after(timeout)
          current(deadline).perform(request, timeout: Deadline.remaining(deadline), **)
        end

        def notify(request, timeout:)
          deadline = Deadline.after(timeout)
          current(deadline).notify(request, timeout: Deadline.remaining(deadline))
        end

        # For a stream, which must stay on the connection it began on.
        def connection = current(nil)

        def greeting = @state.connection.greeting
        def connected? = @state.connected?

        def close
          reconnector = @state.close
          reconnector&.join unless Thread.current == reconnector
          @state.connection&.close
          nil
        end

        private

        def current(deadline)
          @state.current([deadline, Deadline.after(@config.connect_timeout)].compact.min)
        end

        def open_connection
          connection = Connection.new(@config)
          connection.event_handler = @event_handler
          connection.disconnect_handler = -> { lost(connection) }
          connection.connect
          @on_connect.call(connection)
          connection
        rescue StandardError
          connection&.close
          raise
        end

        # A connection that broke before it became current was ignored by #lost, hence the last check. It runs
        # even when on_ready raises, which it likely does on such a connection.
        def install(connection)
          return connection.close unless @state.install(connection)

          begin
            @on_ready.call(connection)
          ensure
            lost(connection) if connection.closed?
          end
        end

        def lost(connection)
          return unless @config.reconnect

          @state.reconnect(connection) do
            Thread.new { reconnect }.tap { |thread| thread.name = "tarantool-reconnect #{@config.address}" }
          end
        end

        def reconnect
          attempt = 0
          while @state.pause(@backoff.delay(attempt))
            connection = attempt_connect
            return install(connection) if connection

            attempt += 1
            return give_up(attempt) if attempt >= @config.reconnect_attempts
          end
        end

        def attempt_connect
          open_connection
        rescue StandardError => e
          @last_error = e
          nil
        end

        def give_up(attempts)
          @state.give_up(
            ConnectionError.new(
              "cannot reconnect to #{@config.address} after #{attempts} attempts: #{@last_error.message}"
            )
          )
        end
      end
    end
  end
end
