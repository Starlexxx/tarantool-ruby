# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Definition do
  describe '#plan and #apply' do
    let(:creation) { Tarantool::Schema::Creation }
    let(:everything) { ['space codes', 'index codes.primary', 'index codes.by_code'] }

    it 'plans what is missing without writing' do
      client = FakeClient.new

      expect(codes_definition.plan(client)).to eq(everything)
      expect(client.creations).to eq([])
    end

    it 'creates what is missing in declaration order' do
      client = FakeClient.new
      client.on_create { |fake| fake.live['codes'] = codes_live }

      expect(codes_definition.apply(client)).to eq(everything)
      expect(client.creations.map(&:first)).to eq([creation::SPACE_LUA, creation::INDEX_LUA, creation::INDEX_LUA])
    end

    it 'does nothing when the live schema matches' do
      client = FakeClient.new('codes' => codes_live)

      expect(codes_definition.apply(client)).to eq([])
      expect(client.creations).to eq([])
    end

    it 'creates nothing when any space drifted' do
      declared = codes_declaration
      definition = described_class.new { %i[codes fresh].each { |name| ensure_space(name, **declared) } }
      client = FakeClient.new('codes' => codes_live.merge('engine' => 'vinyl'))

      expect { definition.apply(client) }.to raise_error(Tarantool::Schema::MismatchError, /engine: declared memtx/)
      expect(client.creations).to eq([])
    end

    it 'fails when something is still missing after creating it' do
      expect { codes_definition.apply(FakeClient.new) }
        .to raise_error(Tarantool::Schema::MismatchError, /space codes:\n    missing after apply/)
    end

    it 'fails for an index of a space declared elsewhere that does not exist' do
      definition = described_class.new { ensure_index(:owned, :by_name, parts: [:name]) }

      expect { definition.plan(FakeClient.new) }
        .to raise_error(Tarantool::Schema::MismatchError, /space owned:\n    missing/)
    end

    it 'fails when a competing deploy changes the space while creating it' do
      client = FakeClient.new
      client.on_create { |fake| fake.live['codes'] = codes_live.merge('engine' => 'vinyl') }

      expect { codes_definition.apply(client) }
        .to raise_error(Tarantool::Schema::MismatchError, /engine: declared memtx/)
      expect(client.creations.size).to eq(3)
    end

    def by_note_index_creation
      ['codes', 'by_note', { 'type' => 'tree', 'unique' => false, 'sequence' => false,
                             'parts' => [{ 'field' => 'note', 'type' => 'string', 'is_nullable' => true }],
                             'if_not_exists' => true }]
    end

    it 'creates an index on a space declared elsewhere with parts inherited from the live format' do
      definition = described_class.new { ensure_index(:codes, :by_note, parts: [:note], unique: false) }
      client = FakeClient.new('codes' => codes_live)
      client.on_create do |fake|
        fake.live['codes']['indexes'] << live_index(2, 'by_note', [[3, 'string', true]], unique: false)
      end

      expect(definition.apply(client)).to eq(['index codes.by_note'])
      expect(client.creations.first.last).to eq(by_note_index_creation)
    end
  end
end
