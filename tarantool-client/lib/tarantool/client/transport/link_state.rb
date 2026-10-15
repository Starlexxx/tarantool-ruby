# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # The current connection of a Link and its state under one lock. Waiters wake on every change.
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

        # Returns false when the link was closed meanwhile.
        def install(connection)
          change do
            next false if @state == :closed

            @connection = connection
            @state = :ready
            true
          end
        end

        # Leaves ready only for the current connection, so a loss is handled once; the block starts the reconnect.
        def reconnect(connection)
          change do
            next unless @state == :ready && @connection.equal?(connection)

            @state = :reconnecting
            @reconnector = yield
          end
        end

        # Returns the reconnect thread, if any, for the caller to join.
        def close
          change do
            @state = :closed
            @error = ClientClosedError.new("connection to #{@address} closed")
            @reconnector
          end
        end

        def give_up(error)
          change do
            next if @state == :closed

            @state = :closed
            @error = error
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
          @lock.synchronize do
            @changed.wait(@lock, delay) unless @state == :closed
            @state != :closed
          end
        end

        private

        # A connection fails its requests before its disconnect handler starts the reconnect; with reconnect
        # on, a request in that gap waits for the next connection instead of failing on the dead one.
        def usable?
          @state == :ready && !(@reconnect && @connection.closed?)
        end

        def change
          @lock.synchronize { yield.tap { @changed.broadcast } }
        end
      end
    end
  end
end
