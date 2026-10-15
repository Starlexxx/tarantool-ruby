# frozen_string_literal: true

RSpec.describe Tarantool::Client::Protocol::Extensions::Datetime do
  let(:factory) { Tarantool::Client::Protocol::Codec::FACTORY }

  def wire(hex)
    [hex].pack('H*')
  end

  {
    'epoch in UTC' => [Time.at(0, in: 'UTC'), 'd7040000000000000000'],
    'nanoseconds with a positive offset' =>
      [Time.at(1_710_061_200, 123_456_789, :nsec, in: '+03:00'), 'd8049076ed650000000015cd5b07b4000000'],
    'a negative offset' => [Time.at(1_700_019_800, in: '-05:30'), 'd804583e54650000000000000000b6fe0000'],
    'a time before 1970' => [Time.at(-315_619_200, 5, :nsec, in: 'UTC'), 'd804800830edffffffff0500000000000000']
  }.each do |name, (time, hex)|
    it "encodes #{name} as Tarantool does" do
      expect(factory.dump(time).unpack1('H*')).to eq(hex)
    end

    it "decodes #{name} with the same instant, nanoseconds and offset" do
      decoded = factory.load(wire(hex))

      expect(decoded).to eq(time)
      expect(decoded).to have_attributes(nsec: time.nsec, utc_offset: time.utc_offset)
    end
  end

  it 'decodes a zero offset as UTC' do
    expect(factory.load(wire('d7040000000000000000'))).to be_utc
  end

  it 'decodes a named zone through its offset, dropping the zone index' do
    expect(factory.load(wire('d804d0cdec650000000000000000b400ee00')))
      .to eq(Time.new(2024, 3, 10, 0, 0, 0, '+03:00')).and have_attributes(utc_offset: 10_800)
  end

  it 'encodes the local offset of a local time' do
    time = Time.now

    decoded = factory.load(factory.dump(time))

    expect(decoded).to have_attributes(utc_offset: time.utc_offset, nsec: time.nsec)
  end

  it 'truncates sub-nanosecond fractions' do
    time = Time.at(0, Rational(3, 2), :nsec, in: 'UTC')

    expect(factory.load(factory.dump(time)).nsec).to eq(1)
  end

  it 'rejects an offset that is not a whole number of minutes' do
    expect { factory.dump(Time.at(0, in: '+00:00:30')) }.to raise_error(ArgumentError, /whole minutes/)
  end

  it 'raises ProtocolError on a payload of unexpected size' do
    payload = response_payload([MessagePack::ExtensionValue.new(4, "\x00".b * 12)])

    expect { Tarantool::Client::Protocol::Codec.decode(payload) }.to raise_error(Tarantool::ProtocolError)
  end
end
