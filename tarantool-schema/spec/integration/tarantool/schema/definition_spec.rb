# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Definition, :integration do
  let(:client) { Tarantool::Client.new(ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301')) }
  let(:created) { ['space schema_codes', 'index schema_codes.primary', 'index schema_codes.by_code'] }

  def exists?(name) = client.eval('return box.space[...] ~= nil', [name]).first

  def create_owned(name_type)
    client.eval(<<~LUA, [name_type])
      local s = box.schema.space.create('schema_owned', {format = {{name = 'id', type = 'unsigned'},
                                                                   {name = 'name', type = ...}}})
      s:create_index('primary', {parts = {'id'}})
    LUA
  end

  after do
    client.eval(<<~LUA, [%w[schema_codes schema_fresh schema_owned schema_docs]])
      for _, name in ipairs(...) do if box.space[name] then box.space[name]:drop() end end
    LUA
    client.close
  end

  it 'creates a space with its indexes and sequence' do
    expect(codes_definition(:schema_codes).apply(client)).to eq(created)
    expect(client.eval("return box.space.schema_codes:insert{box.NULL, 'a'}").first).to eq([1, 'a'])
  end

  it 'does nothing on the second apply' do
    codes_definition(:schema_codes).apply(client)

    expect(codes_definition(:schema_codes).plan(client)).to eq([])
    expect(codes_definition(:schema_codes).apply(client)).to eq([])
  end

  it 'adds an index missing from an existing space' do
    codes_definition(:schema_codes).apply(client)
    declared = codes_declaration
    definition = described_class.new do
      ensure_space(:schema_codes, **declared)
      ensure_index(:schema_codes, :by_note, parts: [:note], unique: false)
    end

    expect(definition.apply(client)).to eq(['index schema_codes.by_note'])
  end

  it 'raises on drift without creating anything' do
    client.eval("box.schema.space.create('schema_codes', {format = {{name = 'id', type = 'unsigned'}, " \
                "{name = 'code', type = 'unsigned'}, {name = 'note', type = 'string', is_nullable = true}}})")
    declared = codes_declaration
    definition = described_class.new { %i[schema_codes schema_fresh].each { |name| ensure_space(name, **declared) } }

    expect { definition.apply(client) }.to raise_error(Tarantool::Schema::MismatchError, /field 2 code: type declared/)
    expect(exists?('schema_fresh')).to be(false)
  end

  it 'adds an index to a space declared elsewhere' do
    create_owned('string')
    definition = described_class.new { ensure_index(:schema_owned, :by_name, parts: [:name]) }

    expect(definition.apply(client)).to eq(['index schema_owned.by_name'])
    expect(definition.apply(client)).to eq([])
  end

  it 'treats a format type alias as the canonical type' do
    create_owned('str')
    definition = described_class.new do
      ensure_space(:schema_owned, format: [{ name: :id, type: :unsigned }, { name: :name, type: :string }],
                                  indexes: [{ name: :primary, parts: [:id] }])
    end

    expect(definition.apply(client)).to eq([])
  end

  it 'round-trips a JSON path part' do
    definition = described_class.new do
      format = [{ name: :id, type: :unsigned }, { name: :meta, type: :map, is_nullable: true }]
      indexes = [{ name: :primary, parts: [:id] },
                 { name: :by_x, parts: [{ field: :meta, path: 'x', type: :string }], unique: false }]
      ensure_space(:schema_docs, format:, indexes:)
    end
    definition.apply(client)

    expect(definition.plan(client)).to eq([])
  end
end
