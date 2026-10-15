# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Space do
  subject(:users) { Tarantool::Crud::Client.new(transport).space(:users) }

  let(:transport) { FakeCaller.new(response) }
  let(:response) { [crud_result([1, 'a']), nil] }

  it 'inserts Arrays with crud.insert_many' do
    expect(users.insert_many([[1, 'a']])).to be_a(Tarantool::Crud::ManyResult).and(be_success)
    expect(transport.last).to have_attributes(function: 'crud.insert_many', arguments: ['users', [[1, 'a']], {}])
  end

  it 'inserts Hashes with crud.insert_object_many' do
    users.insert_many([{ id: 1, name: 'a' }], stop_on_error: true)

    expect(transport.last).to have_attributes(function: 'crud.insert_object_many',
                                              arguments: ['users', [{ id: 1, name: 'a' }], { stop_on_error: true }])
  end

  it 'rejects a mix of Arrays and Hashes' do
    expect { users.insert_many([[1, 'a'], { id: 2 }]) }.to raise_error(ArgumentError)
    expect(transport.requests).to be_empty
  end

  it 'replaces with crud.replace_many and crud.replace_object_many' do
    users.replace_many([[1, 'a']])
    users.replace_many([{ id: 1, name: 'a' }])

    expect(transport.requests.map(&:function)).to eq(%w[crud.replace_many crud.replace_object_many])
  end

  it 'upserts pairs with crud.upsert_many and crud.upsert_object_many' do
    users.upsert_many([[[1, 'a'], [['=', 'name', 'b']]]])
    users.upsert_many([[{ id: 1, name: 'a' }, [['=', 'name', 'b']]]])

    expect(transport.requests.map(&:function)).to eq(%w[crud.upsert_many crud.upsert_object_many])
    expect(transport.last.arguments).to eq(['users', [[{ id: 1, name: 'a' }, [['=', 'name', 'b']]]], {}])
  end

  it 'returns the result from the bang variants when every row succeeded' do
    expect(users.insert_many!([[1, 'a']])).to be_success
  end

  context 'when a row fails' do
    let(:response) { [crud_result([1, 'a']), [crud_error('CallError', 'dup', operation_data: [2, 'b'])]] }

    it 'returns the errors without raising' do
      expect(users.insert_many([[1, 'a'], [2, 'b']]).errors).to contain_exactly(an_instance_of(Tarantool::Crud::CallError))
    end

    it 'raises ManyError carrying the result' do
      expect { users.insert_many!([[1, 'a'], [2, 'b']]) }
        .to raise_error(Tarantool::Crud::ManyError) { |error| expect(error.result.to_a).to eq([{ id: 1, name: 'a' }]) }
    end

    it 'raises ManyError from every bang variant' do
      expect { users.replace_many!([[2, 'b']]) }.to raise_error(Tarantool::Crud::ManyError)
      expect { users.upsert_many!([[[2, 'b'], []]]) }.to raise_error(Tarantool::Crud::ManyError)
    end
  end
end
