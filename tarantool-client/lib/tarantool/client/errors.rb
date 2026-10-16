# frozen_string_literal: true

module Tarantool
  # Base class for every error raised by tarantool-ruby gems.
  class Error < StandardError; end

  # Socket-level failure: refused, lost or broken connection.
  class ConnectionError < Error; end

  # Request issued after the connection was closed by the client.
  class ClientClosedError < ConnectionError; end

  # No response within the request timeout.
  class TimeoutError < Error; end

  # Server rejected the credentials.
  class AuthenticationError < Error
    attr_reader :code

    def initialize(message = nil, code: nil)
      super(message)
      @code = code
    end
  end

  # Malformed or unexpected data from the server.
  class ProtocolError < Error; end

  # Space or index name cannot be resolved.
  class SchemaError < Error; end

  # A Hash tuple names a field missing from the space format.
  class UnknownFieldError < ArgumentError; end

  # Transaction misuse or a transaction that can no longer proceed.
  class TransactionError < Error; end

  # No pool instance can serve a request in the requested mode.
  class NoAvailableInstanceError < Error; end

  # Error returned by the server for a request.
  class ServerError < Error
    attr_reader :code, :error_stack, :schema_version

    def self.from_response(response)
      new(
        response.error_message,
        code: response.error_code, error_stack: response.error_stack, schema_version: response.schema_version
      )
    end

    def initialize(message, code:, error_stack: [], schema_version: nil)
      super(message)
      @code = code
      @error_stack = error_stack
      @schema_version = schema_version
    end
  end
end
