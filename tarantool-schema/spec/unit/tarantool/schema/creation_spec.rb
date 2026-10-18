# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Creation do
  let(:space) { Tarantool::Schema::SpaceSpec.build(:codes, engine: :memtx, **codes_declaration).resolve }
  let(:client) { FakeClient.new }

  it 'creates a space with names and options as eval arguments' do
    described_class::Space.new(spec: space).apply(client)

    expect(client.evals).to eq([[described_class::SPACE_LUA, ['codes', space.to_lua.merge('if_not_exists' => true)]]])
  end

  it 'creates an index with names and options as eval arguments' do
    index = space.indexes.last
    described_class::Index.new(space: :codes, spec: index).apply(client)

    expect(client.evals)
      .to eq([[described_class::INDEX_LUA, ['codes', 'by_code', index.to_lua.merge('if_not_exists' => true)]]])
  end

  it 'sets the whole declared format with the name as an eval argument' do
    described_class::Format.new(space:, fields: space.format.drop(2)).apply(client)

    expect(client.evals).to eq([[described_class::FORMAT_LUA, ['codes', space.format.map(&:to_lua)]]])
  end

  it 'grants the missing privileges as a comma list, resolving the grantee as a user or a role' do
    grant = Tarantool::Schema::GrantSpec.build(:app, %i[write read], on: :codes)
    described_class::Grant.new(spec: grant).apply(client)

    expect(client.evals).to eq([[described_class::GRANT_LUA, ['app', 'read,write', 'codes']]])
    expect(described_class::GRANT_LUA)
      .to include('box.schema.user.exists(grantee) and box.schema.user.grant or box.schema.role.grant')
  end

  it 'describes what it creates' do
    grant = Tarantool::Schema::GrantSpec.build(:app, %i[read write], on: :codes)
    steps = [described_class::Space.new(spec: space), described_class::Format.new(space:, fields: space.format.drop(1)),
             described_class::Index.new(space: :codes, spec: space.indexes.last),
             described_class::Grant.new(spec: grant)]

    expect(steps.map(&:to_s)).to eq(['space codes', 'format codes: add code, note', 'index codes.by_code',
                                     'grant app read,write on codes'])
  end
end
