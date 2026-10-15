# frozen_string_literal: true

RSpec.describe Tarantool::Client::Protocol::Extensions do
  it 'registers MP_ERROR as BoxError without a packer' do
    entry = described_class.find { |extension| extension.type == 0x03 }

    expect(entry).to have_attributes(klass: Tarantool::Client::BoxError, options: { unpacker: an_instance_of(Method) })
  end

  it 'hands every entry to the codec factory' do
    registered = Tarantool::Client::Protocol::Codec::FACTORY.registered_types

    expect(registered.to_h { |type| [type[:type], type[:class]] })
      .to eq(described_class.to_h { |extension| [extension.type, extension.klass] })
  end
end
