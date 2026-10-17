# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Schema do
  let(:raw) do
    {
      'format' => [{ 'name' => 'id', 'type' => 'unsigned' },
                   { 'name' => 'bucket_id', 'type' => 'unsigned', 'is_nullable' => true }, { 'name' => 'meta' }],
      'indexes' => {
        2 => { 'id' => 2, 'name' => 'by_meta', 'type' => 'TREE', 'unique' => false,
               'parts' => [{ 'fieldno' => 3, 'type' => 'string', 'is_nullable' => true, 'exclude_null' => false,
                             'path' => 'x' }] },
        0 => { 'id' => 0, 'name' => 'primary', 'type' => 'TREE', 'unique' => true,
               'parts' => [{ 'fieldno' => 1, 'type' => 'unsigned', 'is_nullable' => false, 'exclude_null' => false }] }
      }
    }
  end

  it 'converts the format to tarantool-schema fields' do
    fields = [{ name: :id, type: 'unsigned', is_nullable: false },
              { name: :bucket_id, type: 'unsigned', is_nullable: true },
              { name: :meta, type: 'any', is_nullable: false }]

    expect(described_class.space(raw)[:format]).to eq(fields)
  end

  it 'converts the indexes in id order with parts named by field' do
    primary = { name: :primary, type: 'tree', unique: true,
                parts: [{ field: :id, type: 'unsigned', is_nullable: false }] }
    by_meta = { name: :by_meta, type: 'tree', unique: false,
                parts: [{ field: :meta, type: 'string', is_nullable: true, path: 'x' }] }

    expect(described_class.space(raw)[:indexes]).to eq([primary, by_meta])
  end

  it 'names a part beyond the format by its position' do
    raw['indexes'][0]['parts'] = [{ 'fieldno' => 9, 'type' => 'unsigned', 'is_nullable' => false }]
    parts = described_class.space(raw)[:indexes].first[:parts]

    expect(parts).to eq([{ field: :'#9', type: 'unsigned', is_nullable: false }])
  end

  it 'keys every space by name' do
    expect(described_class.all({ 'customers' => raw }).keys).to eq([:customers])
  end
end
