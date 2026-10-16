# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Types do
  describe '.declared' do
    it 'accepts canonical names as Symbols or Strings' do
      expect([described_class.declared(:unsigned, 'f'), described_class.declared('map', 'f')]).to eq(%w[unsigned map])
    end

    it 'rejects an alias with the canonical name as a hint' do
      expect { described_class.declared(:str, 'field code') }
        .to raise_error(ArgumentError, 'field code: unknown type "str", use string')
    end

    it 'rejects a differently cased name with a hint' do
      expect { described_class.declared('STRING', 'f') }
        .to raise_error(ArgumentError, 'f: unknown type "STRING", use string')
    end

    it 'rejects an unknown type' do
      expect { described_class.declared(:uint, 'f') }.to raise_error(ArgumentError, 'f: unknown type "uint"')
    end

    it 'freezes the returned name even when given an unfrozen String' do
      expect(described_class.declared(+'unsigned', 'f')).to be_frozen
    end
  end

  describe '.live' do
    it 'maps aliases and case onto canonical names' do
      types = %w[str num STRING Unsigned double].map { |type| described_class.live(type) }

      expect(types).to eq(%w[string number string unsigned double])
    end

    it 'keeps a type it does not know' do
      expect(described_class.live('future')).to eq('future')
    end
  end
end
