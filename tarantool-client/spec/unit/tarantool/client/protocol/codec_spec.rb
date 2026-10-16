# frozen_string_literal: true

require 'stringio'

RSpec.describe Tarantool::Client::Protocol::Codec do
  let(:ping) { Data.define(:type, :body).new(type: 0x40, body: {}) }

  it 'exposes only framing entry points' do
    expect(described_class.singleton_class.public_instance_methods(false))
      .to contain_exactly(:encode, :decode, :read_response, :read_exactly)
  end

  describe '.encode' do
    it 'frames header and body behind a uint32 size prefix' do
      expect(described_class.encode(ping, sync: 1).unpack1('H*')).to eq('ce00000006820040010180')
    end

    it 'adds the stream id to the header' do
      frame = described_class.encode(ping, sync: 1, stream_id: 7)

      expect(described_class.decode(frame.byteslice(5..)).header).to eq(0x00 => 0x40, 0x01 => 1, 0x0a => 7)
    end

    it 'adds the schema version to the header' do
      frame = described_class.encode(ping, sync: 1, schema_version: 80)

      expect(described_class.decode(frame.byteslice(5..)).header).to eq(0x00 => 0x40, 0x01 => 1, 0x05 => 80)
    end
  end

  describe '.read_response' do
    it 'reads one frame from an IO' do
      io = StringIO.new(iproto_frame({ 0x00 => 0, 0x01 => 9, 0x05 => 80 }, { 0x30 => [[1, 'a']] }))

      expect(described_class.read_response(io)).to have_attributes(sync: 9, schema_version: 80, data: [[1, 'a']])
    end

    it 'treats a missing body as empty' do
      io = StringIO.new(iproto_frame({ 0x00 => 0, 0x01 => 9 }))

      expect(described_class.read_response(io).body).to eq({})
    end

    it 'raises EOFError on a truncated frame' do
      io = StringIO.new(iproto_frame({ 0x00 => 0, 0x01 => 9 }, { 0x30 => [] }).byteslice(0, 7))

      expect { described_class.read_response(io) }.to raise_error(EOFError)
    end

    it 'raises ProtocolError on an unexpected size marker' do
      io = StringIO.new("\x01\x00\x00\x00\x00".b)

      expect { described_class.read_response(io) }.to raise_error(Tarantool::ProtocolError)
    end

    it 'raises ProtocolError on malformed msgpack' do
      io = StringIO.new("\xce\x00\x00\x00\x01\xc1".b)

      expect { described_class.read_response(io) }.to raise_error(Tarantool::ProtocolError)
    end

    it 'raises ProtocolError when the declared frame size exceeds max_frame_size' do
      io = StringIO.new([0xce, 100].pack('CN'))

      expect { described_class.read_response(io, max_frame_size: 50) }
        .to raise_error(Tarantool::ProtocolError, 'frame of 100 bytes exceeds max_frame_size 50')
    end
  end

  describe '.decode' do
    it 'raises ProtocolError when the header is not a map' do
      payload = MessagePack.pack([1, 2])

      expect { described_class.decode(payload) }
        .to raise_error(Tarantool::ProtocolError, 'malformed frame: header must be a map with a request type')
    end

    it 'raises ProtocolError when the header has no request type' do
      payload = MessagePack.pack({ 0x01 => 9 })

      expect { described_class.decode(payload) }
        .to raise_error(Tarantool::ProtocolError, 'malformed frame: header must be a map with a request type')
    end

    it 'raises ProtocolError when the body is not a map' do
      payload = MessagePack.pack({ 0x00 => 0, 0x01 => 9 }) + MessagePack.pack(nil)

      expect { described_class.decode(payload) }
        .to raise_error(Tarantool::ProtocolError, 'malformed frame: body must be a map')
    end

    it 'raises ProtocolError on trailing bytes' do
      payload = MessagePack.pack({ 0x00 => 0, 0x01 => 9 }) + MessagePack.pack({}) + MessagePack.pack(1)

      expect { described_class.decode(payload) }
        .to raise_error(Tarantool::ProtocolError, 'malformed frame: trailing bytes')
    end

    it 'decodes a box.error extension value with its cause chain' do
      stack = { 0x00 => [{ 0x00 => 'ClientError', 0x03 => 'boom', 0x05 => 42 }, { 0x03 => 'root', 0x05 => 7 }] }
      body = { 0x30 => [MessagePack::ExtensionValue.new(3, MessagePack.pack(stack))] }
      payload = MessagePack.pack({ 0x00 => 0, 0x01 => 9 }) + MessagePack.pack(body)

      error = described_class.decode(payload).data.first

      expect(error).to be_a(Tarantool::Client::BoxError).and have_attributes(message: 'boom', code: 42)
      expect(error.cause).to have_attributes(message: 'root', code: 7, cause: nil)
    end

    it 'decodes other extension values nested in box.error fields' do
      unknown = MessagePack::ExtensionValue.new(42, 'x')
      stack = { 0x00 => [{ 0x03 => 'boom', 0x06 => { 'id' => unknown } }] }
      body = { 0x30 => [MessagePack::ExtensionValue.new(3, MessagePack.pack(stack))] }
      payload = MessagePack.pack({ 0x00 => 0, 0x01 => 9 }) + MessagePack.pack(body)

      error = described_class.decode(payload).data.first

      expect(error.fields).to eq('id' => unknown)
    end

    it 'decodes a uuid nested in box.error fields' do
      uuid = MessagePack::ExtensionValue.new(2, ['f81d4fae7dec11d0a76500a0c91e6bf6'].pack('H*'))
      stack = { 0x00 => [{ 0x03 => 'boom', 0x06 => { 'id' => uuid } }] }
      body = { 0x30 => [MessagePack::ExtensionValue.new(3, MessagePack.pack(stack))] }
      payload = MessagePack.pack({ 0x00 => 0, 0x01 => 9 }) + MessagePack.pack(body)

      error = described_class.decode(payload).data.first

      expect(error.fields).to eq('id' => Tarantool::Client::UUID.new('f81d4fae-7dec-11d0-a765-00a0c91e6bf6'))
    end

    it 'decodes a box.error nested in box.error fields' do
      inner = MessagePack::ExtensionValue.new(3, MessagePack.pack({ 0x00 => [{ 0x03 => 'inner' }] }))
      stack = { 0x00 => [{ 0x03 => 'outer', 0x06 => { 'origin' => inner } }] }
      body = { 0x30 => [MessagePack::ExtensionValue.new(3, MessagePack.pack(stack))] }
      payload = MessagePack.pack({ 0x00 => 0, 0x01 => 9 }) + MessagePack.pack(body)

      error = described_class.decode(payload).data.first

      expect(error.fields['origin']).to be_a(Tarantool::Client::BoxError).and have_attributes(message: 'inner')
    end

    it 'raises ProtocolError on a malformed box.error extension value' do
      body = { 0x30 => [MessagePack::ExtensionValue.new(3, "\xc1".b)] }
      payload = MessagePack.pack({ 0x00 => 0, 0x01 => 9 }) + MessagePack.pack(body)

      expect { described_class.decode(payload) }.to raise_error(Tarantool::ProtocolError)
    end

    it 'decodes an unknown ext type in the body to a MessagePack::ExtensionValue' do
      body = { 0x30 => [MessagePack::ExtensionValue.new(42, 'x')] }
      payload = MessagePack.pack({ 0x00 => 0, 0x01 => 9 }) + MessagePack.pack(body)

      expect(described_class.decode(payload).data.first).to have_attributes(type: 42, payload: 'x')
    end
  end
end
