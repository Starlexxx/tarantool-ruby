# frozen_string_literal: true

RSpec.describe Tarantool::Client::Protocol::Extensions::Uuid do
  let(:uuid) { Tarantool::Client::UUID.new('f81d4fae-7dec-11d0-a765-00a0c91e6bf6') }
  let(:factory) { Tarantool::Client::Protocol::Codec::FACTORY }
  let(:wire) { ['d802f81d4fae7dec11d0a76500a0c91e6bf6'].pack('H*') }

  it 'encodes a UUID as ext 2 with 16 raw bytes' do
    expect(factory.dump(uuid)).to eq(wire)
  end

  it 'decodes ext 2 into a UUID' do
    expect(factory.load(wire)).to eq(uuid)
  end

  it 'keeps plain strings as MP_STR' do
    expect(factory.dump(uuid.to_s)).to eq(MessagePack.pack(uuid.to_s))
  end

  it 'raises ProtocolError on a payload that is not 16 bytes' do
    payload = response_payload([MessagePack::ExtensionValue.new(2, "\x01".b * 15)])

    expect { Tarantool::Client::Protocol::Codec.decode(payload) }.to raise_error(Tarantool::ProtocolError)
  end
end
