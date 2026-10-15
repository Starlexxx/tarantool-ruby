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
          connected = true
          self
        ensure
          close unless connected
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

        # Closing the attempt first fails a handshake or on_connect blocked on it, so the join is short.
        def close
          reconnector, attempt = @state.close
          attempt&.close
          begin
            reconnector&.join unless Thread.current == reconnector
          ensure
            @state.connection&.close
          end
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
          @state.attempting(connection)
          connection.connect
          @on_connect.call(connection)
          opened = true
          connection
        ensure
          connection&.close unless opened
        end

        # A connection that broke before it became current was ignored by #lost, hence the last check. It runs
        # even when on_ready raises, which it likely does on such a connection.
        def install(connection)
          return connection.close unless @state.install(connection)

          @on_ready.call(connection)
        ensure
          lost(connection) if connection.closed?
        end

        def lost(connection)
          return unless @config.reconnect

          @state.start_reconnect(connection) do |previous|
            Thread.new { reconnect(previous) }.tap { |thread| thread.name = "tarantool-reconnect #{@config.address}" }
          end
        end

        # Joining the previous thread first lets close join only the newest one. Nothing may escape: a dead
        # thread would leave the link reconnecting forever, and its exception would resurface in every join.
        def reconnect(previous)
          previous&.join
          reconnect_with_backoff
        rescue Exception => e # rubocop:disable Lint/RescueException
          warn(e.full_message)
          @state.give_up(ConnectionError.new("reconnect to #{@config.address} failed: #{e.class}: #{e.message}"))
        end

        def reconnect_with_backoff
          attempt = 0
          while @state.pause(@backoff.delay(attempt))
            result = attempt_connect
            return reinstall(result) if result.is_a?(Connection)

            attempt += 1
            return give_up(attempt, result) if attempt >= @config.reconnect_attempts
          end
        end

        def attempt_connect
          open_connection
        rescue StandardError => e
          e
        end

        # The connection stays current: a failed on_ready is the caller's bug, not a reason to drop it.
        def reinstall(connection)
          install(connection)
        rescue StandardError => e
          warn("on_ready failed for #{@config.address}: #{e.full_message}")
        end

        def give_up(attempts, error)
          @state.give_up(
            ConnectionError.new("cannot reconnect to #{@config.address} after #{attempts} attempts: #{error.message}")
          )
        end
      end
    end
  end
end
