# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      # IPROTO framing: MP_UINT32 size prefix, header map, body map.
      module Codec
        SIZE_MARKER = 0xce
        PREFIX_SIZE = 5
        FACTORY = MessagePack::Factory.new

        module_function

        def encode(request, sync:, stream_id: nil, schema_version: nil)
          header = { Constants::REQUEST_TYPE => request.type, Constants::SYNC => sync }
          header[Constants::STREAM_ID] = stream_id if stream_id
          header[Constants::SCHEMA_VERSION] = schema_version if schema_version
          payload = FACTORY.dump(header) + FACTORY.dump(request.body)
          [SIZE_MARKER, payload.bytesize].pack('CN') + payload
        end

        def read_response(io)
          marker, size = read_exactly(io, PREFIX_SIZE).unpack('CN')
          raise ProtocolError, format('unexpected frame size marker 0x%02x', marker) unless marker == SIZE_MARKER

          decode(read_exactly(io, size))
        end

        def decode(payload)
          unpacker = FACTORY.unpacker(allow_unknown_ext: true)
          unpacker.feed(payload)
          header, body = unpack_frame(unpacker)

          validate_header(header)
          validate_body(body)
          raise ProtocolError, 'malformed frame: trailing bytes' unless unpacker.buffer.empty?

          Response.new(header, body)
        end

        def unpack_frame(unpacker)
          header = unpacker.read
          body = unpacker.buffer.empty? ? {} : unpacker.read
          [header, body]
        rescue StandardError => e
          raise ProtocolError, "malformed frame: #{e.message}"
        end

        def validate_header(header)
          return if header.is_a?(Hash) && header.key?(Constants::REQUEST_TYPE)

          raise ProtocolError, 'malformed frame: header must be a map with a request type'
        end

        def validate_body(body)
          raise ProtocolError, 'malformed frame: body must be a map' unless body.is_a?(Hash)
        end

        def read_exactly(io, size)
          data = io.read(size)
          raise EOFError, 'connection closed by server' if data.nil? || data.bytesize < size

          data
        end
      end
    end
  end
end
