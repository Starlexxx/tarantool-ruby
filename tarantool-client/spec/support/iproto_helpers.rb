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

  # An MP_ERROR whose field holds the next one, depth levels in all. Built outside in from precomputed
  # sizes: packing it inside out copies the whole growing payload at every level.
  def nested_box_error(depth)
    leaf = MessagePack.pack({ 0x00 => [{ 0x03 => 'leaf' }] })
    wrapper = MessagePack.pack({ 0x00 => [{ 0x06 => { 'cause' => nil } }] }).chop
    size = leaf.bytesize
    pieces = Array.new(depth - 1) do
      piece = wrapper + mp_error_header(size)
      size += piece.bytesize
      piece
    end

    MessagePack::ExtensionValue.new(0x03, pieces.reverse.join + leaf)
  end

  def mp_error_header(size)
    return [0xc7, size, 0x03].pack('CCC') if size < 0x100
    return [0xc8, size, 0x03].pack('CnC') if size < 0x10000

    [0xc9, size, 0x03].pack('CNC')
  end
end
