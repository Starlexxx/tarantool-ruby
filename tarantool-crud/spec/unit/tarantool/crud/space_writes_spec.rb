# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Space do
  subject(:users) { Tarantool::Crud::Client.new(transport).space(:users) }

  let(:transport) { FakeCaller.new(response) }
  let(:response) { [crud_result([1, 'a']), nil] }

  it 'inserts an Array with crud.insert and returns the row' do
    expect(users.insert([1, 'a'])).to eq(id: 1, name: 'a')
    expect(transport.last).to have_attributes(function: 'crud.insert', arguments: ['users', [1, 'a'], {}])
  end

  it 'inserts a Hash with crud.insert_object' do
    users.insert({ id: 1, name: 'a' })

    expect(transport.last).to have_attributes(function: 'crud.insert_object',
                                              arguments: ['users', { id: 1, name: 'a' }, {}])
  end

  it 'replaces with crud.replace and crud.replace_object' do
    users.replace([1, 'a'])
    users.replace({ id: 1, name: 'a' })

    expect(transport.requests.map(&:function)).to eq(%w[crud.replace crud.replace_object])
  end

  it 'upserts with operations' do
    users.upsert([1, 'a'], [['=', 'name', 'b']])
    users.upsert({ id: 1, name: 'a' }, [['=', 'name', 'b']])

    expect(transport.requests.map(&:function)).to eq(%w[crud.upsert crud.upsert_object])
    expect(transport.last.arguments).to eq(['users', { id: 1, name: 'a' }, [['=', 'name', 'b']], {}])
  end

  it 'gets, updates and deletes by key' do
    users.get(1)
    users.update(1, [['+', 'age', 1]])
    users.delete(1)

    expect(transport.requests.map { |request| [request.function, request.arguments] }).to eq(
      [['crud.get', ['users', 1, {}]], ['crud.update', ['users', 1, [['+', 'age', 1]], {}]],
       ['crud.delete', ['users', 1, {}]]]
    )
  end

  it 'passes options through on top of the write defaults' do
    Tarantool::Crud::Client.new(transport, write: { noreturn: true })
                           .space(:users).insert([1, 'a'], bucket_id: 7, timeout: 1)

    expect(transport.last).to have_attributes(
      arguments: ['users', [1, 'a'], { noreturn: true, bucket_id: 7, timeout: 1 }], timeout: 1.5
    )
  end

  context 'when no row comes back' do
    let(:response) { [crud_result, nil] }

    it 'returns nil' do
      expect(users.get(1)).to be_nil
    end
  end

  context 'when crud returns no result' do
    let(:response) { [nil, nil] }

    it 'returns nil' do
      expect(users.insert([1, 'a'], noreturn: true)).to be_nil
    end
  end

  context 'when crud returns an error' do
    let(:response) { [nil, crud_error('InsertError', 'Duplicate key')] }

    it 'raises it' do
      expect { users.insert([1, 'a']) }.to raise_error(Tarantool::Crud::InsertError, 'Duplicate key')
    end
  end
end
