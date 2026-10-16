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
  end
end
