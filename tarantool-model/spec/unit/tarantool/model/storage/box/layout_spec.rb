# frozen_string_literal: true

RSpec.describe Tarantool::Model::Storage::Box::Layout do
  subject(:layout) { described_class.new(info) }

  let(:client) { Tarantool::Client }
  let(:info) do
    fields = %w[id email age].map { |name| client::SpaceInfo::Field.new(name:, type: 'any', is_nullable: true) }
    part = client::IndexInfo::Part.new(fieldno: 0, name: 'id', type: 'unsigned', is_nullable: false, path: nil)
    primary = client::IndexInfo.new(id: 0, name: 'primary', type: 'tree', unique: true, parts: [part])
    client::SpaceInfo.new(id: 512, name: 'users', fields:, indexes: { 'primary' => primary })
  end

  it 'accepts a model matching the format' do
    expect { layout.verify!(attributes: %i[id age], primary_key: [:id]) }.not_to raise_error
  end

  it 'rejects an attribute missing from the format' do
    expect { layout.verify!(attributes: %i[id phone], primary_key: [:id]) }
      .to raise_error(Tarantool::Model::SchemaMismatchError, /phone/)
  end

  it 'rejects a primary key that differs from the parts of index 0' do
    expect { layout.verify!(attributes: %i[id email], primary_key: [:email]) }
      .to raise_error(Tarantool::Model::SchemaMismatchError, /primary key/)
  end

  context 'without a primary index' do
    let(:info) do
      fields = %w[id email age].map { |name| client::SpaceInfo::Field.new(name:, type: 'any', is_nullable: true) }
      client::SpaceInfo.new(id: 512, name: 'users', fields:, indexes: {})
    end

    it 'rejects the space' do
      expect { layout.verify!(attributes: %i[id age], primary_key: [:id]) }
        .to raise_error(Tarantool::Model::SchemaMismatchError, /no primary index/)
    end
  end
end
