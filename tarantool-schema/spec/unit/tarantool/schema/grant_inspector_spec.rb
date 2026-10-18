# frozen_string_literal: true

RSpec.describe Tarantool::Schema::GrantInspector do
  it 'passes the space and the grantees as eval arguments' do
    client = FakeClient.new
    client.masks['codes'] = { 'app' => 3 }
    client.users = %w[app]

    expect(described_class.call(client, :codes, %i[app other]))
      .to eq(Tarantool::Schema::LiveGrants.new(masks: { 'app' => 3 }, missing: %w[other]))
    expect(client.evals).to eq([[described_class::LUA, ['codes', %w[app other]]]])
  end

  it 'resolves a grantee as a user or a role' do
    expect(described_class::LUA).to include('box.schema.user.exists(grantee) or box.schema.role.exists(grantee)')
  end
end
