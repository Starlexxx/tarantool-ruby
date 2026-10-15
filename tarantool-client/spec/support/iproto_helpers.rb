# frozen_string_literal: true

require 'msgpack'
require 'securerandom'

# Builders for raw IPROTO bytes used by unit specs and FakeTarantool.
module IprotoHelpers
  def iproto_frame(header, body = nil)
    payload = MessagePack.pack(header)
    payload += MessagePack.pack(body) if body

    [0xce, payload.bytesize].pack('CN') + payload
  end

  def response_payload(data)
    MessagePack.pack({ 0x00 => 0, 0x01 => 9 }) + MessagePack.pack({ 0x30 => data })
  end

  def iproto_greeting(version: '2.11.1', salt: SecureRandom.bytes(32))
    banner = "Tarantool #{version} (Binary) 00000000-0000-0000-0000-000000000000"

    "#{banner.ljust(63)}\n#{[salt].pack('m0').ljust(63)}\n"
  end
end
