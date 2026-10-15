# frozen_string_literal: true

RSpec.describe Tarantool::Client::Protocol::Extensions::Decimal do
  let(:factory) { Tarantool::Client::Protocol::Codec::FACTORY }

  def wire(hex)
    [hex].pack('H*')
  end

  {
    '1.23' => 'c7030102123c',
    '-12.345' => 'd6010312345d',
    '0' => 'd501000c',
    '-0' => 'd501000d',
    '100' => 'c7030100100c',
    '1e100' => 'c70301d09c1c',
    '12345678901234567890123456789012345678' => 'c7150100012345678901234567890123456789012345678c'
  }.each do |number, hex|
    it "encodes #{number} as Tarantool does" do
      expect(factory.dump(BigDecimal(number)).unpack1('H*')).to eq(hex)
    end

    it "decodes #{number}" do
      expect(factory.load(wire(hex))).to eq(BigDecimal(number))
    end
  end

  it 'decodes 1e10 from the negative-scale wire format Tarantool itself produces' do
    expect(factory.load(wire('d501f61c'))).to eq(BigDecimal('1e10'))
  end

  it 'encodes 1e10 with trailing zero digits instead of a negative scale' do
    expect(factory.dump(BigDecimal('1e10')).unpack1('H*')).to eq('c707010010000000000c')
  end

  it 'round-trips 0.001' do
    expect(factory.load(factory.dump(BigDecimal('0.001')))).to eq(BigDecimal('0.001'))
  end

  it 'round-trips -1e-38' do
    expect(factory.load(factory.dump(BigDecimal('-1e-38')))).to eq(BigDecimal('-1e-38'))
  end

  it 'decodes the sign of negative zero' do
    expect(factory.load(wire('d501000d')).sign).to eq(BigDecimal::SIGN_NEGATIVE_ZERO)
  end

  it 'decodes digits with a non-negative scale Tarantool writes for whole numbers' do
    expect(factory.load(wire('c7030100100c'))).to eq(BigDecimal('100'))
  end

  it 'treats sign nibble 0x0b as negative' do
    expect(factory.load(wire('d501001b'))).to eq(BigDecimal('-1'))
  end

  it 'rejects NaN and infinities' do
    %w[NaN Infinity -Infinity].each do |special|
      expect { factory.dump(BigDecimal(special)) }.to raise_error(ArgumentError, /cannot encode/)
    end
  end

  it 'rejects more than 38 significant digits' do
    expect { factory.dump(BigDecimal('1' * 39)) }.to raise_error(ArgumentError, /38 digits/)
  end

  it 'raises ProtocolError on a malformed payload' do
    payload = response_payload([MessagePack::ExtensionValue.new(1, "\x00\x1a\x2c".b)])

    expect { Tarantool::Client::Protocol::Codec.decode(payload) }.to raise_error(Tarantool::ProtocolError)
  end
end
