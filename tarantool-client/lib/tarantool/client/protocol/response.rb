# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      # Decoded IPROTO response frame.
      class Response
        attr_reader :header, :body

        def initialize(header, body)
          @header = header
          @body = body
        end

        def type = header.fetch(Constants::REQUEST_TYPE)
        def sync = header[Constants::SYNC]
        def schema_version = header[Constants::SCHEMA_VERSION]
        def data = body[Constants::DATA]
        def error? = type.anybits?(Constants::TYPE_ERROR)
        def push? = type == Constants::CHUNK
        def event? = type == Constants::EVENT
        def event_key = body[Constants::EVENT_KEY]
        def event_data = body[Constants::EVENT_DATA]
        def error_code = type & ~Constants::TYPE_ERROR
        def error_message = body[Constants::ERROR_24]

        def error_stack
          body.fetch(Constants::ERROR, {}).fetch(Constants::ERROR_STACK, []).map do |entry|
            entry.transform_keys(Constants::ERROR_FIELDS)
          end
        end
      end
    end
  end
end
