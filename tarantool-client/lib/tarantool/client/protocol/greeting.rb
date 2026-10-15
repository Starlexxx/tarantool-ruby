# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      # Greeting sent by the server on connect: a 64-byte banner and a 64-byte base64 salt line.
      Greeting = Data.define(:version, :salt) do
        def self.parse(bytes)
          banner = bytes.byteslice(0, 64)
          version = banner[/\ATarantool (\S+)/, 1]
          raise ProtocolError, "unexpected greeting: #{banner.strip.inspect}" unless version

          new(version:, salt: bytes.byteslice(64, 64).strip.unpack1('m'))
        end
      end
    end
  end
end
