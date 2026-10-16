# frozen_string_literal: true

RSpec.describe Tarantool::Model::Storage::Box do
  subject(:storage) { described_class.new(caller, read: { timeout: 1 }, write: { timeout: 2 }) }

  let(:client) { Tarantool::Client }
  let(:caller) { instance_double(Tarantool::Client, space_info: info) }
  let(:info) do
    fields = %w[id email age].map { |name| client::SpaceInfo::Field.new(name:, type: 'any', is_nullable: true) }
    part = client::IndexInfo::Part.new(fieldno: 0, name: 'id', type: 'unsigned', is_nullable: false, path: nil)
    primary = client::IndexInfo.new(id: 0, name: 'primary', type: 'tree', unique: true, parts: [part])
    client::SpaceInfo.new(id: 512, name: 'users', fields:, indexes: { 'primary' => primary })
  end

  it 'rejects mode: for a caller that is not a Pool' do
    expect { described_class.new(caller, read: { mode: :ro }) }.to raise_error(ArgumentError, /Pool/)
  end

  it 'accepts mode: for a Pool' do
    expect { described_class.new(Tarantool::Client::Pool.allocate, write: { mode: :rw }) }.not_to raise_error
  end

  it 'gets a row with the read options' do
    allow(caller).to receive(:select).and_return([[1, 'a', 3]])

    expect(storage.get(:users, [1]).attributes).to eq(id: 1, email: 'a', age: 3)
    expect(caller).to have_received(:select).with(:users, [1], limit: 1, timeout: 1)
  end

  it 'inserts a tuple in format order with the write options' do
    allow(caller).to receive(:insert).and_return([1, 'a', nil])

    expect(storage.insert(:users, { email: 'a', id: 1 }).tuple).to eq([1, 'a', nil])
    expect(caller).to have_received(:insert).with(:users, [1, 'a', nil], timeout: 2)
  end

  it 'raises RecordNotUnique for a duplicate key and keeps the server error as cause' do
    allow(caller).to receive(:insert).and_raise(Tarantool::ServerError.new('Duplicate key exists', code: 3))

    expect { storage.insert(:users, { id: 1 }) }
      .to raise_error(Tarantool::Model::RecordNotUnique) { |error| expect(error.cause).to be_a(Tarantool::ServerError) }
  end

  it 'passes other server errors through' do
    allow(caller).to receive(:update).and_raise(Tarantool::ServerError.new('boom', code: 94))

    expect { storage.update(:users, [1], []) }.to raise_error(Tarantool::ServerError, 'boom')
  end

  it 'returns nil when update or delete find no row' do
    allow(caller).to receive_messages(update: nil, delete: nil)

    expect([storage.update(:users, [1], [['=', 'age', 1]]), storage.delete(:users, [1])]).to eq([nil, nil])
  end

  it 'selects by index 0 for the primary index and leaves out an unset limit' do
    allow(caller).to receive(:select).and_return([])
    storage.select(:users, index: nil, key: [], iterator: :all, limit: nil, after: nil)

    expect(caller).to have_received(:select).with(:users, [], index: 0, iterator: :all, after: nil, timeout: 1)
  end

  it 'selects with a limit and the tuple to continue after' do
    allow(caller).to receive(:select).and_return([[2, 'b', 3]])

    expect(storage.select(:users, index: :age, key: [3], iterator: :ge, limit: 5, after: [1, 'a', 3]).size).to eq(1)
    expect(caller).to have_received(:select)
      .with(:users, [3], index: :age, iterator: :ge, after: [1, 'a', 3], timeout: 1, limit: 5)
  end

  it 'looks up the format with the options of the operation' do
    allow(caller).to receive(:delete).and_return(nil)
    storage.delete(:users, [1])

    expect(caller).to have_received(:space_info).with(:users, timeout: 2)
  end

  it 'does not count' do
    expect { storage.count(:users, index: nil, key: [], iterator: :all) }
      .to raise_error(Tarantool::Model::NotSupportedError)
  end

  it 'verifies a model against the format' do
    expect { storage.verify(:users, attributes: [:phone], primary_key: [:id]) }
      .to raise_error(Tarantool::Model::SchemaMismatchError)
  end
end
