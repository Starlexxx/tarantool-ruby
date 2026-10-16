# frozen_string_literal: true

RSpec.describe Tarantool::Model::Testing::MemoryStorage do
  subject(:storage) { described_class.new({ users: Schemas::USERS, accounts: Schemas::ACCOUNTS }) }

  def server_error(code)
    an_instance_of(Tarantool::ServerError).and(having_attributes(code:))
  end

  def pairs(**)
    described_class.new(
      { pairs: { format: [{ name: :a, type: :unsigned }, { name: :b, type: :unsigned }],
                 indexes: [{ name: :primary, parts: %i[a b] }] } }, **
    ).tap { |memory| [[2, 1], [1, 2], [1, 1]].each { |a, b| memory.insert(:pairs, { a:, b: }) } }
  end

  def nullable_codes
    described_class.new(
      { codes: { format: [{ name: :id, type: :unsigned }, { name: :code, type: :string, is_nullable: true },
                          { name: :note }],
                 indexes: [{ name: :primary, parts: %i[id] }, { name: :code, parts: %i[code] }] } }
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
      expect(row.attributes[:created_at].utc_offset).to eq(3 * 3600)
    end
  end

  describe 'Symbol values in caller keys' do
    def labels
      described_class.new(
        { labels: { format: [{ name: :code, type: :string }, { name: :note }],
                    indexes: [{ name: :primary, parts: %i[code] }] } }
      )
    end

    def ids(rows) = rows.map { |row| row.attributes[:id] }

    def by_email(key, iterator, after: nil)
      ids(storage.select(:users, index: :email, key:, iterator:, limit: nil, after:))
    end

    before { %w[a b].each_with_index { |email, id| storage.insert(:users, { id:, email:, age: 1 }) } }

    it 'matches and orders them as Strings in select and after' do
      expect([by_email([:a], :eq), by_email([:a], :ge), by_email([:a], :ge, after: [0, :a, 1])])
        .to eq([[0], [0, 1], [1]])
    end

    it 'gets, updates and deletes by a Symbol primary key' do
      memory = labels
      memory.insert(:labels, { code: :a, note: 1 })

      results = [memory.get(:labels, [:a]), memory.update(:labels, [:a], [['=', 'note', 2]]),
                 memory.delete(:labels, [:a])]

      expect(results.map(&:attributes)).to eq([{ code: 'a', note: 1 }, { code: 'a', note: 2 }, { code: 'a', note: 2 }])
      expect(memory.select(:labels, index: nil, key: [], iterator: :all, limit: nil, after: nil)).to be_empty
    end

    it 'finds through a model with an untyped primary key attribute' do
      stub_const('Label', Class.new do
        include Tarantool::Model

        self.primary_key = :code
        attribute :code
        attribute :note
      end)
      Label.storage = labels
      Label.create!(code: 'a', note: 1)

      expect([Label.find(:a).code, Label.where(key: [:a]).map(&:code)]).to eq(['a', ['a']])
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
      numbers = described_class.new(
        { numbers: { format: [{ name: :id, type: :number }, { name: :note }],
                     indexes: [{ name: :primary, parts: %i[id] }] } }
      )
      numbers.insert(:numbers, { id: 1, note: 'a' })
      numbers.update(:numbers, [1], [['=', 'id', 1.0]])
      rows = numbers.select(:numbers, index: nil, key: [], iterator: :all, limit: nil, after: nil)

      expect(rows.map { |row| row.attributes[:id] }).to eq([1.0])
      expect(rows.first.attributes[:id]).to be_a(Float)
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

    it 'gets the first row matching a partial primary key, like a select with limit 1' do
      expect([pairs.get(:pairs, [1]).tuple, pairs.get(:pairs, []).tuple, pairs.get(:pairs, [3])])
        .to eq([[1, 1], [1, 1], nil])
    end

    it 'raises ServerError 31 for a get with a key longer than the primary index' do
      expect { pairs.get(:pairs, [1, 1, 1]) }.to raise_error(
        server_error(31).and(having_attributes(message: 'Invalid key part count (expected [0..2], got 3)'))
      )
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

  it_behaves_like 'a model storage', count: false
  it_behaves_like 'a box-compatible storage'

  describe 'reads' do
    def ids(rows) = rows.map { |row| row.attributes[:id] }

    def hashed
      described_class.new(
        { tokens: { format: [{ name: :id, type: :unsigned }, { name: :token, type: :unsigned }],
                    indexes: [{ name: :primary, parts: %i[id] }, { name: :token, parts: %i[token], type: :hash }] } }
      ).tap { |memory| [[1, 30], [2, 10], [3, 20]].each { |id, token| memory.insert(:tokens, { id:, token: }) } }
    end

    def scan(memory, space, **options)
      memory.select(space, index: nil, key: [], iterator: :all, limit: nil, after: nil, **options)
    end

    def prefixed
      described_class.new(
        { pairs: { format: [{ name: :id, type: :unsigned }, { name: :a, type: :unsigned },
                            { name: :b, type: :unsigned }],
                   indexes: [{ name: :primary, parts: %i[id] }, { name: :ab, parts: %i[a b], unique: false }] } }
      ).tap do |memory|
        [[1, 1, 10], [2, 1, 20], [3, 2, 5], [4, 2, 15]].each { |id, a, b| memory.insert(:pairs, { id:, a:, b: }) }
      end
    end

    it 'sorts nil first and matches nil with eq' do
      codes = nullable_codes
      [[1, nil], [2, nil], [3, 'b'], [4, 'a']].each { |id, code| codes.insert(:codes, { id:, code: }) }

      expect(ids(scan(codes, :codes, index: :code))).to eq([1, 2, 4, 3])
      expect(ids(scan(codes, :codes, index: :code, key: ['b'], iterator: :lt))).to eq([4, 2, 1])
      expect(ids(scan(codes, :codes, index: :code, key: [nil], iterator: :eq))).to eq([1, 2])
    end

    it 'reads a hash index with eq, gt and all in key order' do
      expect(ids(scan(hashed, :tokens, index: :token, key: [20], iterator: :gt))).to eq([1])
      expect(ids(scan(hashed, :tokens, index: :token))).to eq([2, 3, 1])
    end

    it 'raises ServerError 112 for other iterators and after on a hash index' do
      expect { scan(hashed, :tokens, index: :token, key: [20], iterator: :ge) }.to raise_error(server_error(112))
      expect { scan(hashed, :tokens, index: :token, after: [1, 30]) }
        .to raise_error(server_error(112).and(having_attributes(message: /pagination/)))
    end

    it 'raises ServerError 136 for a partial key on a multi-part hash index' do
      memory = described_class.new(
        { pairs: { format: [{ name: :id, type: :unsigned }, { name: :a, type: :unsigned },
                            { name: :b, type: :unsigned }],
                   indexes: [{ name: :primary, parts: %i[id] }, { name: :ab, parts: %i[a b], type: :hash }] } }
      )
      message = 'HASH index  does not support selects via a partial key (expected 2 parts, got 1). ' \
                'Please Consider changing index type to TREE.'

      expect { scan(memory, :pairs, index: :ab, key: [1], iterator: :gt) }
        .to raise_error(server_error(136).and(having_attributes(message:)))
      expect(scan(memory, :pairs, index: :ab, key: [1, 2], iterator: :eq)).to eq([])
    end

    it 'takes an index by id, and raises SchemaError for an unknown index' do
      storage.insert(:users, { id: 1, email: 'a', age: 1 })

      expect(ids(scan(storage, :users, index: 0))).to eq([1])
      expect { scan(storage, :users, index: :nope) }.to raise_error(Tarantool::SchemaError, /index 'nope'/)
    end

    it 'raises ArgumentError for an unknown iterator' do
      expect { scan(storage, :users, iterator: :req, key: [1]) }.to raise_error(ArgumentError, /req/)
    end

    it 'raises ArgumentError for an unknown iterator on a hash index too' do
      expect { scan(hashed, :tokens, index: :token, key: [20], iterator: :req) }.to raise_error(ArgumentError, /req/)
    end

    it 'orders a boolean field with false before true' do
      flags = described_class.new(
        { flags: { format: [{ name: :id, type: :unsigned }, { name: :flag, type: :boolean }],
                   indexes: [{ name: :primary, parts: %i[id] }, { name: :flag, parts: %i[flag], unique: false }] } }
      )
      [[1, true], [2, false], [3, true]].each { |id, flag| flags.insert(:flags, { id:, flag: }) }

      expect(ids(scan(flags, :flags, index: :flag))).to eq([2, 1, 3])
    end

    it 'raises ServerError 31 for a key longer than the index' do
      expect { scan(storage, :users, index: :age, key: [1, 2]) }.to raise_error(
        server_error(31).and(having_attributes(message: 'Invalid key part count (expected [0..1], got 2)'))
      )
    end

    it 'matches a key shorter than a two-part index as a prefix' do
      expect(ids(scan(prefixed, :pairs, index: :ab, key: [1], iterator: :eq))).to eq([1, 2])
      expect(ids(scan(prefixed, :pairs, index: :ab, key: [1], iterator: :ge))).to eq([1, 2, 3, 4])
    end

    it 'continues after a tuple matched by a prefix key' do
      first = scan(prefixed, :pairs, index: :ab, key: [1], iterator: :ge, limit: 1)

      expect(ids(scan(prefixed, :pairs, index: :ab, key: [1], iterator: :ge, after: first.last.tuple))).to eq([2, 3, 4])
    end

    it 'does not count, like Storage::Box' do
      expect { storage.count(:users, index: nil, key: [], iterator: :all) }
        .to raise_error(Tarantool::Model::NotSupportedError, /Storage::Box/)
    end
  end

  describe '#transaction' do
    def user(id) = storage.insert(:users, { id:, email: "u#{id}", age: 1 })

    it 'returns the block value and keeps the writes' do
      expect([storage.transaction(isolation: :read_committed) { user(1) && :done }, storage.get(:users, [1])&.tuple])
        .to eq([:done, [1, 'u1', 1]])
    end

    it 'rolls back and re-raises when the block raises' do
      user(1)

      expect { storage.transaction { user(2) && storage.delete(:users, [1]) && raise('boom') } }.to raise_error('boom')
      expect([storage.get(:users, [1])&.tuple, storage.get(:users, [2])]).to eq([[1, 'u1', 1], nil])
    end

    it 'rolls back when the block leaves with throw' do
      catch(:halt) { storage.transaction { user(1) && throw(:halt) } }

      expect(storage.get(:users, [1])).to be_nil
    end

    it 'keeps the sequence moving after a rollback' do
      expect { storage.transaction { storage.insert(:accounts, { id: nil, email: 'a' }) && raise('boom') } }
        .to raise_error('boom')

      expect(storage.insert(:accounts, { id: nil, email: 'a' }).attributes[:id]).to eq(2)
    end

    it 'rejects a nested transaction and keeps the outer one usable' do
      result = storage.transaction do
        expect { storage.transaction { nil } }.to raise_error(Tarantool::TransactionError)
        user(1) && :done
      end

      expect([result, storage.get(:users, [1])&.tuple]).to eq([:done, [1, 'u1', 1]])
    end
  end

  context 'when it behaves like Storage::Crud' do
    subject(:crud) { described_class.new({ users: Schemas::CRUD_USERS }, behaves_like: :crud) }

    def user(id, age = 1) = crud.insert(:users, { id:, email: "u#{id}", age: })

    def ids(rows) = rows.map { |row| row.attributes[:id] }

    it_behaves_like 'a model storage' do
      let(:storage) { described_class.new({ users: Schemas::USERS }, behaves_like: :crud) }
    end

    it_behaves_like 'a crud-compatible storage' do
      let(:storage) { crud }
    end

    it 'skips verify, counts, and refuses transactions' do
      user(1)

      expect([crud.verify(:users, attributes: %i[phone], primary_key: %i[x]),
              crud.count(:users, index: :age, key: [1], iterator: :eq)]).to eq([nil, 1])
      expect { crud.transaction { nil } }.to raise_error(Tarantool::Model::NotSupportedError, /transactions/)
    end

    it 'returns single-row results without a tuple and fills bucket_id' do
      row = user(1)

      expect([row.tuple, crud.get(:users, [1]).tuple, crud.delete(:users, [1]).tuple]).to eq([nil, nil, nil])
      expect(row.attributes[:bucket_id]).to be_between(1, 30_000)
    end

    it 'keeps tuples on select rows' do
      user(1)

      expect(crud.select(:users, index: nil, key: [], iterator: :all, limit: nil, after: nil).map(&:tuple))
        .to all(be_an(Array))
    end

    it 'scans the primary index without a condition, and finds nothing through an unknown index with one' do
      [[1, 30], [2, 20]].each { |id, age| user(id, age) }

      expect(ids(crud.select(:users, index: :age, key: [], iterator: :ge, limit: nil, after: nil))).to eq([1, 2])
      expect([crud.select(:users, index: :nope, key: [1], iterator: :eq, limit: nil, after: nil),
              crud.count(:users, index: :nope, key: [1], iterator: :eq)]).to eq([[], 0])
    end

    it 'raises crud error classes with crud messages' do
      user(1)

      expect { crud.insert(:users, { id: 2, email: 'b' }) }
        .to raise_error(Tarantool::Crud::InsertError, /Failed to flatten object: .*Field "age" isn't nullable/)
      expect { crud.update(:users, [1], [['=', 'id', 5]]) }
        .to raise_error(Tarantool::Crud::UpdateError, /\AFailed to update: Attempt to modify a tuple field/)
      expect { crud.get(:nope, [1]) }.to raise_error(Tarantool::Crud::GetError, 'Space "nope" doesn\'t exist')
    end

    it 'raises GetError for a get whose key does not have every primary key part' do
      expect { pairs(behaves_like: :crud).get(:pairs, [1]) }.to raise_error(
        Tarantool::Crud::GetError, 'Failed to get: Invalid key part count in an exact match (expected 2, got 1)'
      )
      expect { pairs(behaves_like: :crud).get(:pairs, [1, 1, 1]) }.to raise_error(Tarantool::Crud::GetError, /got 3/)
    end

    it 'does not use sequences' do
      memory = described_class.new({ accounts: Schemas::ACCOUNTS }, behaves_like: :crud)

      expect { memory.insert(:accounts, { id: nil, email: 'a' }) }.to raise_error(Tarantool::Crud::InsertError, /"id"/)
    end
  end
end
