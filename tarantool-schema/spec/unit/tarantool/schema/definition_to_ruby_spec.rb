# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Definition do
  describe '#to_ruby' do
    let(:definition) do
      described_class.new do
        ensure_space :codes,
                     format: [
                       { name: :id, type: :unsigned },
                       { name: :code, type: :string },
                       { name: :meta, type: :map, is_nullable: true },
                       { name: :tags, type: :any, is_nullable: true },
                       { name: :flags, type: :unsigned }
                     ],
                     indexes: [
                       { name: :primary, parts: [:id], sequence: true },
                       { name: :by_code, type: :hash, parts: [:code] },
                       { name: :by_x, parts: [{ field: :meta, type: :string, path: 'x' }], unique: false },
                       { name: :by_flags, type: :bitset, parts: [:flags], unique: false },
                       { name: :by_code_scalar, parts: [{ field: :code, type: :scalar }, :id], unique: false }
                     ]
        ensure_space :events, engine: :vinyl,
                              format: [{ name: :id, type: :unsigned }],
                              indexes: [{ name: :primary, parts: [:id] }]
        ensure_index :owned, :by_name, parts: [:name], unique: false
        ensure_index :owned, :by_path, parts: [{ field: :meta, type: :string, path: 'x', is_nullable: true }]
      end
    end

    let(:source) { File.read(File.join(__dir__, '../../../fixtures/definition.txt')) }

    it 'renders the declaration without defaults' do
      expect(definition.to_ruby).to eq(source)
    end

    it 'evaluates back to the same declaration' do
      expect(eval(definition.to_ruby).to_h).to eq(definition.to_h) # rubocop:disable Security/Eval
    end

    it 'quotes names that are not identifiers' do
      definition = described_class.new do
        ensure_space :'my-codes', format: [{ name: :'the id', type: :unsigned }],
                                  indexes: [{ name: :primary, parts: [:'the id'] }]
      end

      expect(definition.to_ruby).to include('ensure_space :"my-codes"', 'name: :"the id"', 'parts: [:"the id"]')
    end

    it 'renders an empty definition' do
      expect(described_class.new.to_ruby).to eq("Tarantool::Schema::Definition.new do\nend\n")
    end

    it 'wraps an index whose line would be too long' do
      parts = Array.new(5) { |i| { field: :"a_very_long_field_name_#{i}", type: :string, path: "key_#{i}" } }
      definition = described_class.new do
        ensure_space :codes, format: [{ name: :id, type: :unsigned }, { name: :meta, type: :map }],
                             indexes: [{ name: :primary, parts: [:id] },
                                       { name: :wide, parts: parts.map { |p| p.merge(field: :meta) }, unique: false }]
      end

      expect(definition.to_ruby.lines.map(&:size).max).to be <= 121
      expect(eval(definition.to_ruby).to_h).to eq(definition.to_h) # rubocop:disable Security/Eval
    end
  end
end
