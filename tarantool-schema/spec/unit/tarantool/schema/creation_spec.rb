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

  it 'describes what it creates' do
    steps = [described_class::Space.new(spec: space),
             described_class::Index.new(space: :codes, spec: space.indexes.last)]

    expect(steps.map(&:to_s)).to eq(['space codes', 'index codes.by_code'])
  end
end
