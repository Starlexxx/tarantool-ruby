# frozen_string_literal: true

RSpec.describe Tarantool::Client::Protocol::Auth::ChapSha1 do
  it 'scrambles the password with the first 20 bytes of salt' do
    salt = (0..31).to_a.pack('C*')

    expect(described_class.scramble('secret', salt).unpack1('H*')).to eq('21b3ff405f32cbe4aafff291396046ea29fa3a4d')
  end
end
