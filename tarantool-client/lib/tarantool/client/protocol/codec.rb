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

        def encode(request, sync:, stream_id: nil)
          header = { Constants::REQUEST_TYPE => request.type, Constants::SYNC => sync }
          header[Constants::STREAM_ID] = stream_id if stream_id
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
          header = unpacker.read
          body = unpacker.buffer.empty? ? {} : unpacker.read
          Response.new(header, body)
        rescue MessagePack::UnpackError, EOFError => e
          raise ProtocolError, "malformed frame: #{e.message}"
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
