# frozen_string_literal: true

# The Storage::Crud contract beyond 'a model storage'. Needs `storage` and an empty `users` space with bucket_id, as
# in spec/integration/crud_init.lua.
RSpec.shared_examples 'a crud-compatible storage' do
  def select(index: nil, key: [], iterator: :all, limit: nil, after: nil)
    storage.select(:users, index:, key:, iterator:, limit:, after:)
  end

  before { storage.insert(:users, { id: 1, email: 'a@x', age: 1 }) }

  it 'returns single-row results without a tuple and fills bucket_id' do
    row = storage.get(:users, [1])

    expect([row.tuple, row.attributes[:bucket_id]]).to match([nil, an_instance_of(Integer)])
  end

  it 'raises InsertError for nil in a non-nullable field' do
    expect { storage.insert(:users, { id: 2, email: 'b@x' }) }
      .to raise_error(Tarantool::Crud::InsertError, /Field "age" isn't nullable/)
  end

  it 'raises UpdateError for a changed primary key' do
    expect { storage.update(:users, [1], [['=', 'id', 5]]) }
      .to raise_error(Tarantool::Crud::UpdateError, /\AFailed to update: Attempt to modify a tuple field/)
  end

  it 'raises UpdateError and DeleteError for a key that is not the whole primary key' do
    expect { storage.update(:users, [1, 2], [['=', 'age', 2]]) }.to raise_error(
      Tarantool::Crud::UpdateError, 'Failed to update: Invalid key part count in an exact match (expected 1, got 2)'
    )
    expect { storage.delete(:users, []) }
      .to raise_error(Tarantool::Crud::DeleteError, /\AFailed to delete: Invalid key part count .*got 0/)
  end

  it 'raises the operation error for an unknown space' do
    expect { storage.get(:nope, [1]) }.to raise_error(Tarantool::Crud::GetError, /Space "nope" doesn't exist/)
  end

  it 'scans without a condition whatever index is named, and finds nothing through an unknown index' do
    expect([select(index: :nope).size, select(index: :nope, key: [1], iterator: :eq)]).to eq([1, []])
  end

  it 'does not check the schema, not even that the space exists' do
    expect(storage.verify(:nope, attributes: %i[phone], primary_key: %i[x])).to be_nil
  end

  it 'refuses transactions' do
    expect(storage.supports_transactions?).to be(false)
    expect { storage.transaction { nil } }.to raise_error(Tarantool::Model::NotSupportedError)
  end
end
