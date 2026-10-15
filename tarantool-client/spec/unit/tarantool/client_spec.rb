# frozen_string_literal: true

RSpec.describe Tarantool::Client do
  let(:server) do
    FakeTarantool.new do |request, fake|
      space_id = request.body[0x10]
      case space_id
      when 281 then fake.reply(request, [[512, 1, 'users']])
      when 289 then fake.reply(request, [[512, 0, 'primary']])
      else fake.reply(request, [[space_id, request.body[0x20]]])
      end
    end
  end
  let(:client) { described_class.new(server.uri, user: 'app', password: 'secret') }

  after do
    client.close
    server.stop
  end

  it 'reports the server version' do
    expect(client.server_version).to eq('2.11.1')
  end

  it 'resolves names through the loaded schema' do
    expect(client.select(:users, 7, index: :primary)).to eq([[512, [7]]])
  end

  it 'raises SchemaError for unknown names after a reload' do
    expect { client.select(:orders, 1) }.to raise_error(Tarantool::SchemaError)
  end
end
