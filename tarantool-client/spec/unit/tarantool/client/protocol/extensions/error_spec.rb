# frozen_string_literal: true

RSpec.describe Tarantool::Client::Protocol::Extensions::Error do
  def decode(error)
    Tarantool::Client::Protocol::Codec.decode(response_payload([error])).data.first
  end

  def depth(error) = error.fields&.fetch('cause')&.then { |cause| 1 + depth(cause) } || 1

  it 'decodes errors nested in fields up to 16 levels' do
    expect(depth(decode(nested_box_error(16)))).to eq(16)
  end

  it 'raises ProtocolError on errors nested deeper than 16 levels' do
    expect { decode(nested_box_error(17)) }.to raise_error(Tarantool::ProtocolError, /nested deeper than 16/)
  end

  it 'raises ProtocolError instead of overflowing the stack on very deep nesting' do
    expect { decode(nested_box_error(30_000)) }.to raise_error(Tarantool::ProtocolError)
  end

  it 'starts counting afresh after a rejected payload' do
    expect { decode(nested_box_error(17)) }.to raise_error(Tarantool::ProtocolError)

    expect(depth(decode(nested_box_error(16)))).to eq(16)
  end
end
