# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # The current connection of a Link and its state under one lock. Waiters wake on every state change.
      class LinkState
        attr_reader :connection

        def initialize(address, reconnect:)
          @address = address
          @reconnect = reconnect
          @lock = Mutex.new
          @changed = ConditionVariable.new
          @state = :connecting
        end

        def connected?
          @lock.synchronize { @state == :ready && !@connection.closed? }
        end

        # Records the connection being opened so that close can abort it; raises once the link is closed.
        def attempting(connection)
          @lock.synchronize do
            raise @error.exception(@error.message) if @state == :closed

            @attempt = connection
          end
        end

        # Returns false when the link was closed meanwhile.
        def install(connection)
          @lock.synchronize do
            next false if @state == :closed

            @connection = connection
            @attempt = nil
            @state = :ready
            @changed.broadcast
            true
          end
        end

        # Leaves ready only for the current connection, so a loss is handled once. The block gets the previous
        # reconnect thread and returns the new one; the state flips only once that thread exists.
        def start_reconnect(connection)
          @lock.synchronize do
            next unless @state == :ready && @connection.equal?(connection)

            @reconnector = yield @reconnector
            @state = :reconnecting
            @changed.broadcast
          end
        end

        # Returns the reconnect thread and the connection it is opening, for the caller to abort and join.
        def close
          @lock.synchronize do
            @error = ClientClosedError.new("connection to #{@address} closed")
            unless @state == :closed
              @state = :closed
              @changed.broadcast
            end
            [@reconnector, @attempt]
          end
        end

        def give_up(error)
          @lock.synchronize do
            next if @state == :closed

            @state = :closed
            @error = error
            @changed.broadcast
          end
        end

        def current(wait_until)
          @lock.synchronize do
            loop do
              return @connection if usable?
              raise @error.exception(@error.message) if @state == :closed

              remaining = Deadline.remaining(wait_until)
              raise ConnectionError, "not connected to #{@address}" if remaining&.zero?

              @changed.wait(@lock, remaining)
            end
          end
        end

        # Returns false once closed; close cuts the sleep short.
        def pause(delay)
          wake_at = Deadline.after(delay)

          @lock.synchronize do
            until @state == :closed || (remaining = Deadline.remaining(wake_at)).zero?
              @changed.wait(@lock, remaining)
            end
            @state != :closed
          end
        end

        private

        # A connection fails its requests before its disconnect handler starts the reconnect; with reconnect
        # on, a request in that gap waits for the next connection instead of failing on the dead one.
        def usable?
          @state == :ready && !(@reconnect && @connection.closed?)
        end
      end
    end
  end
end
