# frozen_string_literal: true

require 'socket'

module Tarantool
  class Client
    module Transport
      # One multiplexed IPROTO connection. Any number of threads or fibers may
      # perform requests concurrently; a reader thread routes responses by sync.
      # @api private
      class Connection
        attr_reader :greeting, :server_features
        attr_writer :event_handler, :disconnect_handler

        def initialize(config)
          @config = config
          @pending = PendingRequests.new
        end

        def connect
          establish

          self
        rescue StandardError
          close
          raise
        end

        # A request sent with no time left could still run on the server while the caller gets TimeoutError.
        def perform(request, timeout:, stream_id: nil, schema_version: nil, on_push: nil)
          deadline = Deadline.after(timeout)
          raise TimeoutError, "no response within #{timeout}s" if Deadline.remaining(deadline)&.zero?

          sync, future = @pending.register
          frame = Protocol::Codec.encode(request, sync:, stream_id:, schema_version:)
          response = exchange(frame, future, deadline, timeout, &on_push)
          raise ServerError.from_response(response) if response.error?

          response
        ensure
          @pending.delete(sync) if sync
        end

        # For requests the server never answers (WATCH, UNWATCH): there is no sync to wait on.
        def notify(request, timeout:)
          write(Protocol::Codec.encode(request, sync: 0), Deadline.after(timeout))
        end

        def close
          @pending.fail_all(ClientClosedError.new("connection to #{@config.address} closed"))
          @socket&.close
          ThreadJoin.join(@reader)

          nil
        end

        def closed?
          !@pending.failure.nil?
        end

        private

        def establish
          deadline = Deadline.after(@config.connect_timeout)
          @socket = open_socket(deadline)
          @writer = FrameWriter.new(@socket)
          @greeting = read_greeting(deadline)
          start_reader

          @server_features = Handshake.perform(self, @config, deadline)
        rescue IOError, SystemCallError, SocketError, TimeoutError, ServerError => e
          raise ConnectionError, "cannot connect to #{@config.address}: #{e.message}"
        end

        def open_socket(deadline)
          return UNIXSocket.new(@config.path) if @config.path

          Socket.tcp(@config.host, @config.port, connect_timeout: Deadline.remaining(deadline)).tap do |socket|
            socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
          end
        end

        def read_greeting(deadline)
          Protocol::Greeting.parse(TimedRead.read_exactly(@socket, Protocol::Constants::GREETING_SIZE, deadline))
        end

        def start_reader
          @reader = Thread.new { read_loop }

          @reader.name = "tarantool-reader #{@config.address}"
        end

        def read_loop
          loop { route(Protocol::Codec.read_response(@socket, max_frame_size: @config.max_frame_size)) }
        rescue IOError, SystemCallError, ProtocolError => e
          reason = e.message
        rescue StandardError, SystemStackError => e
          reason = "#{e.class}: #{e.message}"
        ensure
          break_connection("connection to #{@config.address} lost: #{reason || 'reader stopped'}")
        end

        # Events carry the sync of whichever WATCH triggered them, so they are routed by type.
        def route(response)
          return @pending.push(response.sync, response.data.first) if response.push?
          return @event_handler&.call(response.event_key, response.event_data) if response.event?

          @pending.resolve(response.sync, response)
        end

        # A write that runs out of time, waiting for the lock or for the socket, is reported like a missing reply.
        def exchange(frame, future, deadline, timeout, &)
          write(frame, deadline)

          future.value(Deadline.remaining(deadline), &)
        rescue TimeoutError
          raise TimeoutError, "no response within #{timeout}s"
        end

        # A partially written frame corrupts the stream, so any interruption after the
        # first byte (deadline, IO error, Thread#raise, Timeout) kills the connection.
        def write(frame, deadline)
          @writer.write(frame, deadline) { break_connection("write to #{@config.address} did not complete") }
        rescue IOError, SystemCallError => e
          failure = @pending.failure
          raise failure.exception(failure.message) if failure

          raise ConnectionError, "write to #{@config.address} failed: #{e.message}"
        end

        # The handler hears only of a loss: close records ClientClosedError first, so it stays silent.
        def break_connection(message)
          lost = @pending.fail_all(ConnectionError.new(message))
          @socket&.close

          @disconnect_handler&.call if lost
        end
      end
    end
  end
end
