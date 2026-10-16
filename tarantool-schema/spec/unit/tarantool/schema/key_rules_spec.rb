# frozen_string_literal: true

RSpec.describe Tarantool::Schema::KeyRules do
  def index(type:, parts:, unique: true)
    Tarantool::Schema::IndexSpec.new(name: :by_x, type: type.to_s, unique:, parts:, sequence: false)
  end

  def part(field: :note, type: nil, is_nullable: nil, path: nil)
    Tarantool::Schema::PartSpec.new(field:, type:, is_nullable:, path:)
  end

  it 'rejects a tree part of a type the server does not index' do
    expect { described_class.check(index(type: :tree, parts: [part(type: 'map')]), nil) }
      .to raise_error(ArgumentError, 'index by_x: part note of type map can not be indexed by tree')
  end

  it 'rejects a hash part of a type the server does not index' do
    expect { described_class.check(index(type: :hash, parts: [part(type: 'any')]), nil) }
      .to raise_error(ArgumentError, 'index by_x: part note of type any can not be indexed by hash')
  end

  it 'requires a hash index to be unique' do
    expect { described_class.check(index(type: :hash, unique: false, parts: [part(type: 'unsigned')]), nil) }
      .to raise_error(ArgumentError, 'index by_x: hash index must be unique')
  end

  it 'rejects nullable hash parts' do
    expect { described_class.check(index(type: :hash, parts: [part(type: 'unsigned', is_nullable: true)]), nil) }
      .to raise_error(ArgumentError, 'index by_x: hash index can not have nullable part note')
  end

  it 'allows nullable tree parts' do
    expect { described_class.check(index(type: :tree, parts: [part(type: 'unsigned', is_nullable: true)]), nil) }
      .not_to raise_error
  end

  it 'skips unresolved part attributes' do
    expect { described_class.check(index(type: :hash, parts: [part]), nil) }.not_to raise_error
  end

  it 'prefixes the message with the context' do
    expect { described_class.check(index(type: :hash, unique: false, parts: [part(type: 'unsigned')]), 'space codes') }
      .to raise_error(ArgumentError, 'space codes: index by_x: hash index must be unique')
  end

  it 'leaves bitset and rtree indexes alone' do
    expect { described_class.check(index(type: :bitset, unique: false, parts: [part(type: 'map')]), nil) }
      .not_to raise_error
  end
end
