# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Inspector do
  it 'passes the space name as an eval argument' do
    client = FakeClient.new('codes' => codes_live)

    expect(described_class.call(client, :codes)).to be_a(Tarantool::Schema::LiveSpace)
    expect(client.evals).to eq([[described_class::LUA, ['codes']]])
  end

  it 'returns nil for a missing space' do
    expect(described_class.call(FakeClient.new, :codes)).to be_nil
  end
end
