# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      # Greeting sent by the server on connect: a 64-byte banner and a 64-byte base64 salt line.
      # @api private
      Greeting = Data.define(:version, :salt) do
        self::BANNER_VERSION = /\ATarantool (\S+)/

        def self.parse(bytes)
          banner = bytes.byteslice(0, 64)
          version = banner[Greeting::BANNER_VERSION, 1]
          raise ProtocolError, "unexpected greeting: #{banner.strip.inspect}" unless version

          new(version:, salt: bytes.byteslice(64, 64).strip.unpack1('m'))
        end
      end
    end
  end
end
