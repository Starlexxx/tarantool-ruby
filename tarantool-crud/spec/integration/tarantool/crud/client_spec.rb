# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Client, :integration do
  subject(:crud) { described_class.new(connection) }

  let(:uri) { ENV.fetch('TARANTOOL_CRUD_URI', 'tcp://app:secret@localhost:3311') }
  let(:connection) { Tarantool::Client.new(uri) }
  let(:customers) { crud.space(:customers) }
  let(:five) { (1..5).map { |id| [id, nil, "c#{id}", id * 10] } }

  before { customers.truncate }
  after { connection.close }

  it 'inserts tuples and objects and gets them back' do
    customers.insert([1, nil, 'a', 20])
    customers.insert({ id: 2, name: 'b', age: 30 })

    expect(customers.get(1)).to include(id: 1, name: 'a', age: 20)
    expect(customers.get(2)).to include(id: 2, name: 'b', age: 30)
    expect(customers.get(3)).to be_nil
  end

  it 'updates and replaces rows' do
    customers.insert([1, nil, 'a', 20])

    expect(customers.update(1, [['+', 'age', 1]])).to include(age: 21)
    expect(customers.replace({ id: 1, name: 'b', age: 5 })).to include(name: 'b', age: 5)
  end

  it 'upserts and deletes rows' do
    2.times { customers.upsert([1, nil, 'a', 1], [['+', 'age', 1]]) }

    expect(customers.get(1)).to include(age: 2)
    expect(customers.delete(1)).to include(id: 1)
    expect(customers.get(1)).to be_nil
  end

  it 'selects with Hash conditions and continues after a row' do
    customers.insert_many(five)
    page = customers.select({ age: 20.. }, first: 2)

    expect(page.map { |row| row[:age] }).to eq([20, 30])
    expect(customers.select({ age: 20.. }, first: 2, after: page.last).map { |row| row[:age] }).to eq([40, 50])
  end

  it 'iterates over every row in batches' do
    customers.insert_many(five)

    expect(customers.each(batch_size: 2).map { |row| row[:id] }).to match_array(1..5)
  end

  it 'counts, measures and finds borders' do
    customers.insert_many(five)

    expect(customers.count({ age: 30.. }, timeout: 1)).to eq(3)
    expect(customers.len).to eq(5)
    expect([customers.min(:age_index)[:age], customers.max(:age_index)[:age]]).to eq([10, 50])
  end

  it 'reports failed rows of a batch' do
    customers.insert([1, nil, 'a', 1])
    result = customers.insert_many([[1, nil, 'dup', 1], [2, nil, 'b', 2]])

    expect(result.map { |row| row[:id] }).to eq([2])
    expect(result.errors).to contain_exactly(
      an_instance_of(Tarantool::Crud::CallError).and(having_attributes(operation_data: start_with(1)))
    )
  end

  it 'raises ManyError from a bang batch' do
    customers.insert([1, nil, 'a', 1])

    expect { customers.insert_many!([[1, nil, 'dup', 1]]) }.to raise_error(Tarantool::Crud::ManyError)
  end

  it 'raises crud errors' do
    customers.insert([1, nil, 'a', 1])

    expect { customers.insert([1, nil, 'a', 1]) }.to raise_error(Tarantool::Crud::InsertError, /Duplicate key/)
  end

  it 'reads the schema through the router' do
    schema = crud.schema(:customers)

    expect(schema[:format].map { |field| field[:name] }).to eq(%i[id bucket_id name age])
    expect(schema[:indexes].first).to include(name: :primary, unique: true)
    expect(crud.schema.keys).to include(:customers)
  end

  it 'raises SchemaError for an unknown space' do
    expect { crud.schema(:nope) }.to raise_error(Tarantool::Crud::SchemaError, /nope/)
  end

  it 'reads storage info and stats' do
    expect(crud.storage_info.values).to all(include('status' => 'running'))
    expect(crud.stats(:customers)).to include('truncate')
    expect(crud.stats).to include('spaces')
  end

  it 'works over a pool' do
    pool = Tarantool::Client::Pool.new([uri])
    space = described_class.new(pool).space(:customers)
    space.insert([1, nil, 'a', 1])

    expect(space.get(1)).to include(name: 'a')
  ensure
    pool&.close
  end
end
