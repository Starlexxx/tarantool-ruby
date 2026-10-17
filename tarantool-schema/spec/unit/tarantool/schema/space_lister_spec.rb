# frozen_string_literal: true

RSpec.describe Tarantool::Schema::SpaceLister do
  it 'lists the user spaces with a constant eval without arguments' do
    client = FakeClient.new('codes' => codes_live, 'users' => codes_live)

    expect(described_class.call(client)).to eq(%i[codes users])
    expect(client.evals).to eq([[described_class::LUA, []]])
  end

  it 'skips system ids and underscore names in Lua' do
    expect(described_class::LUA).to include('box.schema.SYSTEM_ID_MAX', "'^_'")
  end

  it 'returns the given names without asking the server' do
    client = FakeClient.new('codes' => codes_live)

    expect(described_class.call(client, only: ['users', :_bucket])).to eq(%i[users _bucket])
    expect(client.evals).to eq([])
  end
end
