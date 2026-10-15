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

  it 'builds a tuple in format order, nil for missing attributes' do
    expect(layout.to_tuple({ age: 3, id: 1 })).to eq([1, nil, 3])
  end

  it 'builds a row with the raw tuple, nil for fields beyond it' do
    expect(layout.to_row([1, 'a'])).to eq(Tarantool::Model::Row.new(attributes: { id: 1, email: 'a', age: nil },
                                                                    tuple: [1, 'a']))
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
end
