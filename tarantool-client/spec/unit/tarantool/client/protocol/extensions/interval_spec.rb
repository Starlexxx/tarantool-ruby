# frozen_string_literal: true

RSpec.describe Tarantool::Client::Protocol::Extensions::Interval do
  let(:factory) { Tarantool::Client::Protocol::Codec::FACTORY }
  let(:interval) { Tarantool::Client::Interval }

  def wire(hex)
    [hex].pack('H*')
  end

  {
    'an empty interval' => [{}, 'c70306010801'],
    'every unit with adjust :last' =>
      [{ year: 1, month: -2, week: 3, day: 4, hour: 5, min: 6, sec: 7, nsec: 8, adjust: :last },
       'c7130609000101fe0203030404050506060707080802'],
    'adjust :excess, which Tarantool omits' => [{ day: -1, adjust: :excess }, 'c703060103ff'],
    'one unit with adjust :none' => [{ month: 1 }, 'c705060201010801']
  }.each do |name, (attributes, hex)|
    it "encodes #{name} as Tarantool does" do
      expect(factory.dump(interval.new(**attributes)).unpack1('H*')).to eq(hex)
    end

    it "decodes #{name}" do
      expect(factory.load(wire(hex))).to eq(interval.new(**attributes))
    end
  end

  it 'rejects an unknown adjust' do
    expect { factory.dump(interval.new(adjust: :snap)) }.to raise_error(ArgumentError, /unknown interval adjust/)
  end

  {
    'an unknown field id' => "\x01\x09\x01",
    'an unknown adjust value' => "\x01\x08\x07",
    'a count that does not match the pairs' => "\x02\x03\x01",
    'a non-integer value' => "\x01\x03\xa1a"
  }.each do |name, bytes|
    it "raises ProtocolError on #{name}" do
      payload = response_payload([MessagePack::ExtensionValue.new(6, bytes.b)])

      expect { Tarantool::Client::Protocol::Codec.decode(payload) }.to raise_error(Tarantool::ProtocolError)
    end
  end
end
