# frozen_string_literal: true

require 'stringio'

RSpec.describe Tarantool::Client::Protocol::Codec do
  let(:ping) { Data.define(:type, :body).new(type: 0x40, body: {}) }

  describe '.encode' do
    it 'frames header and body behind a uint32 size prefix' do
      expect(described_class.encode(ping, sync: 1).unpack1('H*')).to eq('ce00000006820040010180')
    end

    it 'adds the stream id to the header' do
      frame = described_class.encode(ping, sync: 1, stream_id: 7)

      expect(described_class.decode(frame.byteslice(5..)).header).to eq(0x00 => 0x40, 0x01 => 1, 0x0a => 7)
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
  end
end
