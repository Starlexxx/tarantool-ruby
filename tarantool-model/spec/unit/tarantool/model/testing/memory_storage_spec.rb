# frozen_string_literal: true

RSpec.describe Tarantool::Model::Testing::MemoryStorage do
  subject(:storage) { described_class.new(users: Schemas::USERS, accounts: Schemas::ACCOUNTS) }

  def server_error(code)
    an_instance_of(Tarantool::ServerError).and(having_attributes(code:))
  end

  def nullable_codes
    described_class.new(
      codes: { format: [{ name: :id, type: :unsigned }, { name: :code, type: :string, is_nullable: true },
                        { name: :note }],
               indexes: [{ name: :primary, parts: %i[id] }, { name: :code, parts: %i[code] }] }
    )
  end

  it 'accepts the normalized form of a tarantool-schema definition' do
    hash = {
      users: {
        engine: 'memtx', format: [{ name: :id, type: 'unsigned', is_nullable: false }],
        indexes: [{ name: :primary, parts: [{ field: :id, type: 'unsigned', is_nullable: false, path: nil }],
                    unique: true, type: 'tree', sequence: true }]
      }
    }
    definition = Object.new.tap { |object| object.define_singleton_method(:to_h) { hash } }

    expect(described_class.from_definition(definition).insert(:users, { id: nil }).attributes).to eq(id: 1)
  end

  describe 'value round trip through the wire codec' do
    it 'turns Symbol keys into String keys in an any field' do
      row = storage.insert(:accounts, { id: 1, email: 'a@x', tags: { color: :red } })

      expect(row.attributes[:tags]).to eq('color' => 'red')
    end

    it 'round-trips BigDecimal, UUID, Interval and a Time with offset equal' do
      balance = BigDecimal('12.50')
      token = Tarantool::Client::UUID.new('550e8400-e29b-41d4-a716-446655440000')
      period = Tarantool::Client::Interval.new(year: 1, month: 2)
      created_at = Time.new(2024, 1, 1, 12, 0, 0, '+03:00')

      row = storage.insert(:accounts, { id: 1, email: 'a@x', balance:, token:, created_at:, period: })

      expect(row.attributes).to include(balance:, token:, created_at:, period:)
    end
  end

  describe 'writes' do
    before { storage.insert(:users, { id: 1, email: 'a@x', age: 1 }) }

    it 'returns rows with attributes and the tuple' do
      row = Tarantool::Model::Row.new(attributes: { id: 1, email: 'a@x', age: 1 }, tuple: [1, 'a@x', 1])

      expect(storage.get(:users, [1])).to eq(row)
    end

    it 'raises RecordNotUnique for a duplicate unique secondary key on insert and update' do
      storage.insert(:users, { id: 2, email: 'b@x', age: 1 })

      expect { storage.insert(:users, { id: 3, email: 'a@x', age: 1 }) }
        .to raise_error(Tarantool::Model::RecordNotUnique, /unique index "email" in space "users"/)
      expect { storage.update(:users, [2], [['=', 'email', 'a@x']]) }.to raise_error(Tarantool::Model::RecordNotUnique)
    end

    it 'raises RecordNotUnique for a duplicate primary key, with the old and new tuple in the message' do
      expect { storage.insert(:users, { id: 1, email: 'c@x', age: 2 }) }.to raise_error(
        Tarantool::Model::RecordNotUnique,
        'Duplicate key exists in unique index "primary" in space "users" with old tuple - [1, "a@x", 1] ' \
        'and new tuple - [1, "c@x", 2]'
      )
    end

    it 'overwrites the original row when a numeric primary key changes type but not value' do
      storage.update(:users, [1], [['=', 'id', 1.0]])

      expect(storage.get(:users, [1]).attributes[:id]).to be_a(Float)
    end

    it 'lets an update keep its own unique keys' do
      expect(storage.update(:users, [1], [['=', 'email', 'a@x'], ['=', 'id', 1]]).attributes).to include(email: 'a@x')
    end

    it 'raises ServerError 23 for nil in a non-nullable field, with the server text' do
      expect { storage.insert(:users, { id: 2, email: 'b@x' }) }.to raise_error(
        server_error(23).and(having_attributes(message: 'Tuple field 3 (age) type does not match one required ' \
                                                        'by operation: expected unsigned, got nil'))
      )
      expect { storage.update(:users, [1], [['=', 'age', nil]]) }.to raise_error(server_error(23))
    end

    it 'accepts nil in nullable and untyped fields, and several nils in a unique index' do
      codes = nullable_codes
      codes.insert(:codes, { id: 1 })

      expect(codes.insert(:codes, { id: 2 }).attributes).to eq(id: 2, code: nil, note: nil)
    end

    it 'raises ServerError 94 when an update changes the primary key' do
      expect { storage.update(:users, [1], [['=', 'id', 5]]) }.to raise_error(server_error(94))
      expect(storage.get(:users, [5])).to be_nil
    end

    it 'adds and subtracts, and raises ServerError 26 for a non-number' do
      expect(storage.update(:users, [1], [['+', 'age', 5], ['-', 'age', 2]]).attributes[:age]).to eq(4)
      expect { storage.update(:users, [1], [['+', 'email', 1]]) }.to raise_error(server_error(26))
    end

    it 'raises ServerError 201 for an unknown field and NotSupportedError for other operators' do
      expect { storage.update(:users, [1], [['=', 'nope', 1]]) }.to raise_error(server_error(201))
      expect { storage.update(:users, [1], [['!', 'age', 1]]) }.to raise_error(Tarantool::Model::NotSupportedError)
    end

    it 'leaves the row unchanged when an update fails' do
      expect { storage.update(:users, [1], [['=', 'age', 9], ['+', 'email', 1]]) }.to raise_error(Tarantool::ServerError)
      expect(storage.get(:users, [1]).attributes[:age]).to eq(1)
    end

    it 'raises Tarantool::SchemaError for an unknown space' do
      expect { storage.get(:nope, [1]) }.to raise_error(Tarantool::SchemaError, "space 'nope' not found")
    end

    it 'takes String keys and rejects attributes missing from the format' do
      expect(storage.insert(:users, { 'id' => 2, 'email' => 'b@x', 'age' => 1 }).attributes).to include(id: 2)
      expect { storage.insert(:users, { id: 3, email: 'c@x', age: 1, phone: 'x' }) }
        .to raise_error(ArgumentError, /no field 'phone'/)
    end

    it 'returns nil for a missing key' do
      expect([storage.get(:users, [9]), storage.update(:users, [9], []), storage.delete(:users, [9])])
        .to eq([nil, nil, nil])
    end

    it 'never shares values with the caller' do
      email = +'a@y'
      storage.update(:users, [1], [['=', 'email', email]])
      email << '!'
      storage.get(:users, [1]).attributes[:email] << '?'

      expect(storage.get(:users, [1]).attributes[:email]).to eq('a@y')
    end
  end

  describe 'sequence' do
    let(:account_sequence) { (1..).each }

    def account(id = nil)
      storage.insert(:accounts, { id:, email: "#{id.inspect}#{account_sequence.next}" }).attributes[:id]
    end

    it 'fills a nil primary key from 1 and moves past explicit values' do
      expect([account, account(10), account]).to eq([1, 10, 11])
    end

    it 'never gives values back after delete or a failed insert' do
      first = account
      storage.delete(:accounts, [first])
      expect { storage.insert(:accounts, { id: nil, email: nil }) }.to raise_error(server_error(23))

      expect(account).to eq(first + 2)
    end

    it 'is not used for spaces without a sequence' do
      expect { storage.insert(:users, { id: nil, email: 'a', age: 1 }) }.to raise_error(server_error(23))
    end

    it 'does not move the counter for an explicit non-integer primary key' do
      storage.insert(:accounts, { id: 2.5, email: 'a' })

      expect(account).to eq(1)
    end
  end
end
