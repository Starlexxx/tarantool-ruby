# frozen_string_literal: true

# One declared space and the matching eval result of Inspector, shared by the unit specs.
module SchemaFixtures
  def codes_declaration
    {
      format: [{ name: :id, type: :unsigned }, { name: :code, type: :string },
               { name: :note, type: :string, is_nullable: true }],
      indexes: [{ name: :primary, parts: [:id], sequence: true }, { name: :by_code, parts: [:code] }]
    }
  end

  def codes_live
    {
      'engine' => 'memtx',
      'format' => [{ 'name' => 'id', 'type' => 'unsigned' }, { 'name' => 'code', 'type' => 'string' },
                   { 'name' => 'note', 'type' => 'string', 'is_nullable' => true }],
      'indexes' => [live_index(0, 'primary', [[1, 'unsigned']], sequence: true),
                    live_index(1, 'by_code', [[2, 'string']])]
    }
  end

  def live_index(id, name, parts, type: 'TREE', unique: true, sequence: false, func: false)
    {
      'id' => id, 'name' => name, 'type' => type, 'unique' => unique, 'sequence' => sequence, 'func' => func,
      'parts' => parts.map do |fieldno, part_type, nullable = false|
        { 'fieldno' => fieldno, 'type' => part_type, 'is_nullable' => nullable }
      end
    }
  end

  def codes_definition(name = :codes)
    declaration = codes_declaration

    Tarantool::Schema::Definition.new { ensure_space(name, **declaration) }
  end
end
