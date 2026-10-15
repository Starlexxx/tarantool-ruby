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
          @write_lock = Mutex.new
        end

        def connect
          establish
          self
        rescue StandardError
          close
          raise
        end

        def perform(request, timeout:, stream_id: nil)
          sync, future = @pending.register
          write(Protocol::Codec.encode(request, sync:, stream_id:))
          response = future.value(timeout)
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
          @socket = open_socket
          @greeting = read_greeting
          @reader = Thread.new { read_loop }
          handshake
        rescue IOError, SystemCallError, SocketError => e
          raise ConnectionError, "cannot connect to #{@config.address}: #{e.message}"
        end

        def open_socket
          return UNIXSocket.new(@config.path) if @config.path

          Socket.tcp(@config.host, @config.port, connect_timeout: @config.connect_timeout).tap do |socket|
            socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
          end
        end

        def read_greeting
          @socket.timeout = @config.connect_timeout
          Protocol::Greeting.parse(Protocol::Codec.read_exactly(@socket, Protocol::Constants::GREETING_SIZE))
        ensure
          @socket.timeout = nil
        end

        def handshake
          id = Protocol::Requests::Id.new(
            version: Protocol::Constants::PROTOCOL_VERSION, features: Protocol::Constants::CLIENT_FEATURES
          )
          @server_features = perform(id, timeout: @config.connect_timeout).body.fetch(Protocol::Constants::FEATURES, [])
          authenticate if @config.user && @config.user != 'guest'
        end

        def authenticate
          scramble = Protocol::Auth::ChapSha1.scramble(@config.password.to_s, greeting.salt)
          request = Protocol::Requests::Auth.new(
            user: @config.user, mechanism: Protocol::Auth::ChapSha1::MECHANISM, scramble:
          )
          perform(request, timeout: @config.connect_timeout)
        rescue ServerError => e
          raise AuthenticationError, e.message
        end

        def read_loop
          loop do
            response = Protocol::Codec.read_response(@socket)
            @pending.resolve(response.sync, response)
          end
        rescue IOError, SystemCallError, ProtocolError => e
          @pending.fail_all(ConnectionError.new("connection to #{@config.address} lost: #{e.message}"))
        end

        def write(frame)
          @write_lock.synchronize { @socket.write(frame) }
        rescue IOError, SystemCallError => e
          raise ConnectionError, "write to #{@config.address} failed: #{e.message}"
        end
      end
    end
  end
end
