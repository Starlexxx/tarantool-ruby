# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Extensions
        # MP_EXT uuid: 16 raw bytes in RFC 4122 order.
        # @api private
        module Uuid
          SIZE = 16

          module_function

          def pack(uuid)
            [uuid.value.delete('-')].pack('H*')
          end

          def unpack(payload)
            raise ArgumentError, "malformed uuid: #{payload.bytesize} bytes" unless payload.bytesize == SIZE

            Client::UUID.new(payload.unpack('H8H4H4H4H12').join('-'))
          end

          Extensions.register(Constants::MP_UUID, Client::UUID, packer: method(:pack), unpacker: method(:unpack))
        end
      end
    end
  end
end
