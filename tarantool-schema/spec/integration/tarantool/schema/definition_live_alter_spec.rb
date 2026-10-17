# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Definition, :integration do
  let(:client) { Tarantool::Client.new(ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301')) }

  let(:docs) do
    described_class.new do
      ensure_space :schema_docs,
                   format: [{ name: :id, type: :unsigned }, { name: :meta, type: :map, is_nullable: true }],
                   indexes: [{ name: :primary, parts: [:id], sequence: true },
                             { name: :by_x, parts: [{ field: :meta, type: :string, path: 'x' }], unique: false }]
    end
  end

  let(:wider) do
    declared = codes_declaration
    format = [*declared[:format], { name: :phone, type: :string, is_nullable: true },
              { name: :archived_at, type: :unsigned, is_nullable: true }]
    described_class.new { ensure_space(:schema_codes, **declared, format:) }
  end

  after do
    client.eval(<<~LUA, [%w[schema_codes schema_docs]])
      for _, name in ipairs(...) do if box.space[name] then box.space[name]:drop() end end
    LUA
    client.close
  end

  def live_format = client.eval('return box.space.schema_codes:format()').first.map { |field| field['name'] }

  it 'reads a live space back into a definition that plans nothing and renders to the same declaration' do
    codes_definition(:schema_codes).apply(client)
    live = described_class.from_live(client, only: [:schema_codes])

    expect(live.plan(client)).to eq([])
    expect(live.to_h).to eq(codes_definition(:schema_codes).to_h)
    expect(eval(live.to_ruby).to_h).to eq(live.to_h) # rubocop:disable Security/Eval
  end

  it 'round-trips a JSON path part' do
    docs.apply(client)
    live = described_class.from_live(client, only: [:schema_docs])

    expect(live.to_h).to eq(docs.to_h)
    expect(live.plan(client)).to eq([])
  end

  it 'appends nullable fields to a space holding tuples' do
    codes_definition(:schema_codes).apply(client)
    client.insert(:schema_codes, [1, 'a', nil])

    expect(wider.apply(client, alter: [:add_field])).to eq(['format schema_codes: add phone, archived_at'])
    expect(client.select(:schema_codes, [1], as: :hash))
      .to eq([{ id: 1, code: 'a', note: nil, phone: nil, archived_at: nil }])
    expect(wider.apply(client, alter: [:add_field])).to eq([])
  end

  it 'refuses a field that is not nullable and leaves the format alone' do
    codes_definition(:schema_codes).apply(client)
    declared = codes_declaration
    format = [*declared[:format], { name: :flag, type: :unsigned }]
    definition = described_class.new { ensure_space(:schema_codes, **declared, format:) }

    expect { definition.apply(client, alter: [:add_field]) }
      .to raise_error(Tarantool::Schema::MismatchError, /field 4 flag: must be is_nullable: true to be added/)
    expect(live_format).to eq(%w[id code note])
  end
end
