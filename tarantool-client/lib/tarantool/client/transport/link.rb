# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Keeps one instance connected. Owns the current Connection; once it is lost, a background thread
      # opens new ones with backoff while requests wait for one to become ready.
      # States: connecting -> ready -> draining | reconnecting -> closed.
      # @api private
      class Link
        include LinkEvents
        include LinkDraining

        attr_writer :event_handler

        # on_connect runs on each new connection before requests can use it and may raise to fail the attempt;
        # on_ready runs once the connection is current; on_lost runs when a reconnect starts, before its first attempt.
        def initialize(config, on_connect:, on_ready:, on_lost: nil, backoff: nil, instrumentation: nil)
          @config = config
          @on_connect = on_connect
          @on_ready = on_ready
          @on_lost = on_lost
          @backoff = backoff || Backoff.new(base: config.reconnect_delay, max: config.reconnect_max_delay)
          @state = LinkState.new(config.address, reconnect: config.reconnect)
          @instrumentation = instrumentation
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

        # For requests that must stay on one connection: a stream, or a request resolved by name.
        def connection(deadline = nil) = current(deadline)

        def greeting = @state.connection.greeting
        def connected? = @state.connected?

        # Closing the attempt first fails a handshake or on_connect blocked on it, so the join is short. Closing
        # the connection wakes the drain thread, so it is joined last.
        def close
          reconnector, attempt, drainer = @state.close
          attempt&.close
          begin
            ThreadJoin.join(reconnector)
          ensure
            @state.connection&.close
            ThreadJoin.join(drainer)
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
          return report_lost(connection) unless @config.reconnect

          @state.start_reconnect(connection) do |previous|
            Thread.new { reconnect(previous, connection) }.tap do |thread|
              thread.name = "tarantool-reconnect #{@config.address}"
            end
          end
        rescue ThreadError => e
          fail_reconnect(ConnectionError.new("cannot reconnect to #{@config.address}: #{e.message}"))
        end

        # Joining the previous thread first lets close join only the newest one. Nothing may escape: a dead
        # thread would leave the link reconnecting forever, and its exception would resurface in every join.
        def reconnect(previous, connection)
          ThreadJoin.join(previous)
          emit('disconnect.tarantool', reason: connection.failure&.message)
          run_hook('on_lost') { @on_lost&.call }

          reconnect_with_backoff
        rescue StandardError => e
          Diagnostics.warn(@config.logger, e.full_message)
          fail_reconnect(ConnectionError.new("reconnect to #{@config.address} failed: #{e.class}: #{e.message}"))
        end

        def reconnect_with_backoff
          attempt = 0

          while @state.pause(@backoff.delay(attempt))
            result = attempt_connect
            return reconnected(result, attempt + 1) if result.is_a?(Connection)

            attempt += 1
            return give_up(attempt, result) if attempt >= @config.reconnect_attempts
          end
        end

        def attempt_connect
          open_connection
        rescue StandardError => e
          e
        end
      end
    end
  end
end
