# frozen_string_literal: true

RSpec.describe Tarantool::Schema::FieldSpec do
  it 'fills Tarantool defaults' do
    expect(described_class.build({ name: 'blob' }))
      .to eq(described_class.new(name: :blob, type: 'any', is_nullable: false))
  end

  it 'normalizes names and types' do
    field = described_class.build({ name: :id, type: :unsigned, is_nullable: true })

    expect(field.to_h).to eq(name: :id, type: 'unsigned', is_nullable: true)
  end

  it 'rejects unsupported field options' do
    expect { described_class.build({ name: :id, type: :unsigned, default: 0 }) }
      .to raise_error(ArgumentError, 'field id: unsupported :default')
  end

  it 'rejects a non-boolean is_nullable' do
    expect { described_class.build({ name: :id, is_nullable: 1 }) }
      .to raise_error(ArgumentError, 'field id is_nullable: expected true or false, got 1')
  end

  it 'rejects an entry that is not a Hash' do
    expect { described_class.build(:id) }.to raise_error(ArgumentError, 'format entry must be a Hash, got :id')
  end

  it 'rejects an entry without a name' do
    expect { described_class.build({ type: :unsigned }) }.to raise_error(ArgumentError, 'format entry without name')
  end

  it 'builds Lua format entries with String keys' do
    expect(described_class.build({ name: :id, type: :unsigned }).to_lua)
      .to eq('name' => 'id', 'type' => 'unsigned', 'is_nullable' => false)
  end
end
