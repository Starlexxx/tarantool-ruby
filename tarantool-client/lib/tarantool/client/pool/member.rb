# frozen_string_literal: true

module Tarantool
  class Client
    class Pool
      # One pool address: its client once connected and the role from the instance's latest box.status.
      # An address that is down at start keeps being retried in the background.
      # @api private
      class Member
        include Pool::MemberForkSafety
        include Pool::MemberRole

        def initialize(uri, options)
          @uri = uri
          @options = options
          @config = Configuration.build(uri, **options)
          @instrumentation = Instrumentation.build(@config)
          @lock = Mutex.new
          @changed = ConditionVariable.new
          @closed = false
        end

        def address = @config.address
        def client = @lock.synchronize { @client }
        def inspect = "#<#{self.class.name} #{address}>"

        # Connects and waits up to connect_timeout for the first box.status. Returns the error when the
        # instance is unreachable.
        def start
          connect
          wait_for_status

          nil
        rescue Error => e
          retry_in_background if @config.reconnect
          e
        end

        # nil while disconnected or before the current connection's first box.status, else whether the
        # instance is read-only. The role is dropped as soon as the connection is lost; it can briefly come
        # back only while the watcher dispatcher still delivers that connection's queued box.status.
        def read_only
          @lock.synchronize { @read_only if @client&.connected? }
        end

        def close
          retrier, client = @lock.synchronize do
            @closed = true
            @changed.broadcast
            [@retrier, @client]
          end
          ThreadJoin.join(retrier)

          client&.close
        end

        private

        def connect
          client = Client.new(@uri, **@options)
          # A role belongs to one session; the next one must report its own before the member is routed to.
          client.disconnect_handler = -> { @lock.synchronize { @read_only = nil } }
          client.watch('box.status') { |_key, status| update(status) }

          install(client)
        rescue Error
          client&.close
          raise
        end

        def install(client)
          closed = @lock.synchronize do
            @client = client unless @closed
            @closed
          end

          client.close if closed
        end

        def wait_for_status
          deadline = Transport::Deadline.after(@config.connect_timeout)

          @lock.synchronize do
            while @read_only.nil? && !@closed
              remaining = Transport::Deadline.remaining(deadline)
              break if remaining&.zero?

              @changed.wait(@lock, remaining)
            end
          end
        end

        def retry_in_background
          @lock.synchronize do
            next if @closed

            @retrier = Thread.new { retry_connect }
            @retrier.name = "tarantool-pool-connect #{address}"
          end
        end

        # The thread must never die with an exception: #close joins it and would re-raise it.
        def retry_connect
          backoff = Backoff.new(base: @config.reconnect_delay, max: @config.reconnect_max_delay)
          attempt = 0

          while attempt < @config.reconnect_attempts && pause(backoff.delay(attempt))
            return if try_connect

            attempt += 1
          end
        rescue StandardError => e
          Diagnostics.warn(@config.logger, "tarantool pool: gave up connecting to #{address}: #{e.class}: #{e.message}")
        end

        def try_connect
          connect

          true
        rescue Error
          false
        rescue StandardError => e
          Diagnostics.warn(@config.logger, "tarantool pool: connecting to #{address} failed: #{e.class}: #{e.message}")
          false
        end

        def pause(delay)
          @lock.synchronize do
            @changed.wait(@lock, delay) unless @closed
            !@closed
          end
        end
      end
    end
  end
end
