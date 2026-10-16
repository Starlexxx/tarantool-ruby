# frozen_string_literal: true

RSpec.describe Tarantool::Schema::PartSpec do
  let(:note) { Tarantool::Schema::FieldSpec.new(name: :note, type: 'string', is_nullable: true) }

  it 'takes a bare field name' do
    expect(described_class.build(:note))
      .to eq(described_class.new(field: :note, type: nil, is_nullable: nil, path: nil))
  end

  it 'inherits type and nullability from the field' do
    expect(described_class.build(:note).inherit(note).to_h)
      .to eq(field: :note, type: 'string', is_nullable: true, path: nil)
  end

  it 'keeps what the part declares itself' do
    part = described_class.build({ field: :note, type: :string, is_nullable: false })

    expect(part.inherit(note).is_nullable).to be(false)
  end

  it 'requires a type for a JSON path part' do
    expect { described_class.build({ field: :meta, path: 'x' }) }
      .to raise_error(ArgumentError, 'index part meta: a part with path needs a type')
  end

  it 'rejects collations' do
    expect { described_class.build({ field: :note, collation: 'unicode_ci' }) }
      .to raise_error(ArgumentError, 'index part note: unsupported :collation')
  end

  it 'rejects a nil field' do
    expect { described_class.build(nil) }.to raise_error(ArgumentError, 'index part without field')
  end

  it 'rejects an entry with an explicit nil field' do
    expect { described_class.build({ field: nil }) }.to raise_error(ArgumentError, 'index part without field')
  end

  it 'leaves undeclared options out of the Lua part' do
    expect(described_class.build(:note).to_lua).to eq('field' => 'note')
  end

  it 'passes a path to Lua as declared' do
    expect(described_class.build({ field: :meta, path: 'x', type: :string }).to_lua)
      .to eq('field' => 'meta', 'type' => 'string', 'path' => 'x')
  end
end
