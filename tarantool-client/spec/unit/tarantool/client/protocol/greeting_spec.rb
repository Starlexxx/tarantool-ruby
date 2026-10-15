# frozen_string_literal: true

RSpec.describe Tarantool::Client::Protocol::Greeting do
  let(:salt) { (0..31).to_a.pack('C*') }

  it 'parses server version and salt' do
    greeting = described_class.parse(iproto_greeting(version: '3.2.1', salt:))

    expect(greeting).to have_attributes(version: '3.2.1', salt:)
  end

  it 'rejects a non-Tarantool banner' do
    expect { described_class.parse('HTTP/1.1 400 Bad Request'.ljust(128)) }
      .to raise_error(Tarantool::ProtocolError, /unexpected greeting/)
  end
end
