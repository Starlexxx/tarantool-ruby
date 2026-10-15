# frozen_string_literal: true

require 'socket'

module Tarantool
  class Client
    module Transport
      # One multiplexed IPROTO connection. Any number of threads or fibers may
      # perform requests concurrently; a reader thread routes responses by sync.
      class Connection
        attr_reader :greeting, :server_features

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

        def perform(request, timeout:, stream_id: nil, schema_version: nil)
          deadline = Deadline.after(timeout)
          sync, future = @pending.register
          write(Protocol::Codec.encode(request, sync:, stream_id:, schema_version:), deadline)
          response = await(future, deadline, timeout)
          raise ServerError.from_response(response) if response.error?

          response
        ensure
          @pending.delete(sync) if sync
        end

        def close
          @pending.fail_all(ClientClosedError.new("connection to #{@config.address} closed"))
          @socket&.close
          @reader&.join unless Thread.current == @reader
          nil
        end

        private

        def establish
          deadline = Deadline.after(@config.connect_timeout)
          @socket = open_socket(deadline)
          @writer = FrameWriter.new(@socket)
          @greeting = read_greeting(deadline)
          start_reader
          handshake(deadline)
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
          @socket.timeout = Deadline.remaining(deadline)
          Protocol::Greeting.parse(Protocol::Codec.read_exactly(@socket, Protocol::Constants::GREETING_SIZE))
        ensure
          @socket.timeout = nil
        end

        def handshake(deadline)
          id = Protocol::Requests::Id.new(
            version: Protocol::Constants::PROTOCOL_VERSION, features: Protocol::Constants::CLIENT_FEATURES
          )
          response = perform(id, timeout: Deadline.remaining(deadline))
          @server_features = response.body.fetch(Protocol::Constants::FEATURES, [])
          authenticate(deadline) if @config.user && @config.user != 'guest'
        end

        def authenticate(deadline)
          scramble = Protocol::Auth::ChapSha1.scramble(@config.password.to_s, greeting.salt)
          request = Protocol::Requests::Auth.new(
            user: @config.user, mechanism: Protocol::Auth::ChapSha1::MECHANISM, scramble:
          )
          perform(request, timeout: Deadline.remaining(deadline))
        rescue ServerError => e
          raise AuthenticationError, e.message
        end

        def start_reader
          @reader = Thread.new { read_loop }
          @reader.name = "tarantool-reader #{@config.address}"
        end

        # Push frames share the request's sync; callbacks for them are not supported yet.
        def read_loop
          loop do
            response = Protocol::Codec.read_response(@socket)
            @pending.resolve(response.sync, response) unless response.push?
          end
        rescue IOError, SystemCallError, ProtocolError => e
          reason = e.message
        rescue StandardError => e
          reason = "#{e.class}: #{e.message}"
        ensure
          break_connection("connection to #{@config.address} lost: #{reason || 'reader stopped'}")
        end

        def await(future, deadline, timeout)
          future.value(Deadline.remaining(deadline))
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

        def break_connection(message)
          @pending.fail_all(ConnectionError.new(message))
          @socket&.close
        end
      end
    end
  end
end
