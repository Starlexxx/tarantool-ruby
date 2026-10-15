# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # IPROTO_ID feature exchange, then chap-sha1 AUTH for a named user. Returns the server features.
      module Handshake
        module_function

        def perform(connection, config, deadline)
          id = Protocol::Requests::Id.new(
            version: Protocol::Constants::PROTOCOL_VERSION, features: Protocol::Constants::CLIENT_FEATURES
          )
          response = connection.perform(id, timeout: Deadline.remaining(deadline))
          authenticate(connection, config, deadline) if config.user && config.user != 'guest'
          response.body.fetch(Protocol::Constants::FEATURES, [])
        end

        def authenticate(connection, config, deadline)
          scramble = Protocol::Auth::ChapSha1.scramble(config.password.to_s, connection.greeting.salt)
          request = Protocol::Requests::Auth.new(
            user: config.user, mechanism: Protocol::Auth::ChapSha1::MECHANISM, scramble:
          )
          connection.perform(request, timeout: Deadline.remaining(deadline))
        rescue ServerError => e
          raise AuthenticationError.new(e.message, code: e.code)
        end

        private_class_method :authenticate
      end
    end
  end
end
