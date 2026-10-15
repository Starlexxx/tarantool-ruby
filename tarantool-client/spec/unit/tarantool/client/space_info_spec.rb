# frozen_string_literal: true

RSpec.describe Tarantool::Client::SpaceInfo do
  subject(:info) { described_class.from_tuples(space, indexes) }

  let(:format) do
    [
      { 'name' => 'id', 'type' => 'unsigned' },
      { 'name' => 'age', 'type' => 'unsigned', 'is_nullable' => true },
      { 'name' => 'meta' }
    ]
  end
  let(:space) { [512, 1, 'users', 'memtx', 0, {}, format] }
  let(:indexes) do
    [
      [512, 1, 'age', 'tree', { 'unique' => false }, [{ 'field' => 1, 'type' => 'unsigned', 'is_nullable' => true }]],
      [512, 0, 'primary', 'tree', { 'unique' => true }, [[0, 'unsigned']]],
      [512, 2, 'meta_x', 'tree', { 'unique' => false }, [{ 'field' => 2, 'type' => 'string', 'path' => 'x' }]],
      [512, 3, 'extra', 'hash', { 'unique' => true }, [[5, 'string']]]
    ]
  end
  let(:part) { Tarantool::Client::IndexInfo::Part }

  it 'reads id, name and fields from the space tuple' do
    field = described_class::Field
    expect([info.id, info.name]).to eq([512, 'users'])
    expect(info.fields).to eq(
      [
        field.new(name: 'id', type: 'unsigned', is_nullable: false),
        field.new(name: 'age', type: 'unsigned', is_nullable: true),
        field.new(name: 'meta', type: 'any', is_nullable: false)
      ]
    )
  end

  it 'keys indexes by name in id order' do
    expect(info.indexes.keys).to eq(%w[primary age meta_x extra])
    expect(info.indexes['extra']).to have_attributes(id: 3, type: 'hash', unique: true)
  end

  it 'reads parts in the short array form' do
    expect(info.indexes['primary'].parts)
      .to eq([part.new(fieldno: 0, name: 'id', type: 'unsigned', is_nullable: false, path: nil)])
  end

  it 'reads nullable and path parts in the map form' do
    expect(info.indexes['age'].parts.first).to have_attributes(fieldno: 1, name: 'age', is_nullable: true)
    expect(info.indexes['meta_x'].parts.first).to have_attributes(name: 'meta', type: 'string', path: 'x')
  end

  it 'leaves the name of a part beyond the format nil' do
    expect(info.indexes['extra'].parts.first).to have_attributes(fieldno: 5, name: nil)
  end

  it 'returns the index with id 0 as the primary index' do
    expect(info.primary_index.name).to eq('primary')
  end

  context 'with a space without format and indexes' do
    let(:space) { [600, 1, 'raw'] }
    let(:indexes) { [] }

    it 'has no fields, no indexes and no primary index' do
      expect([info.fields, info.indexes, info.primary_index]).to eq([[], {}, nil])
    end
  end
end
