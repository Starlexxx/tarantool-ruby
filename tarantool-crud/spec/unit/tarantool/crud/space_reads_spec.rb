# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Space do
  subject(:users) { Tarantool::Crud::Client.new(transport).space(:users) }

  let(:transport) { FakeCaller.new(response) }
  let(:response) { [crud_result([1, 'a'], [2, 'b']), nil] }

  it 'selects every row without conditions' do
    expect(users.select.to_a).to eq([{ id: 1, name: 'a' }, { id: 2, name: 'b' }])
    expect(transport.last).to have_attributes(function: 'crud.select', arguments: ['users', nil, {}])
  end

  it 'selects with conditions and options' do
    users.select({ age: 18.. }, first: 10)

    expect(transport.last.arguments).to eq(['users', [['>=', 'age', 18]], { first: 10 }])
  end

  it 'sends a Hash row given as after as its tuple' do
    users.select(nil, after: { id: 1, name: 'a' })
    users.select(nil, after: [2, 'b'])

    expect(transport.requests.map { |request| request.arguments.last })
      .to eq([{ after: [1, 'a'] }, { after: [2, 'b'] }])
  end

  it 'finds borders by index' do
    expect(users.min(:age_index)).to eq(id: 1, name: 'a')
    users.max

    expect(transport.requests.map(&:arguments)).to eq([['users', :age_index, {}], ['users', nil, {}]])
  end

  it 'gives min only the read defaults it accepts' do
    Tarantool::Crud::Client.new(transport, read: { mode: 'read', prefer_replica: true }).space(:users).min(:age_index)

    expect(transport.last.arguments).to eq(['users', :age_index, { mode: 'read' }])
  end

  context 'when counting' do
    let(:response) { [3, nil] }

    it 'returns the number' do
      expect(users.count({ name: 'a' })).to eq(3)
      expect(transport.last).to have_attributes(function: 'crud.count', arguments: ['users', [['==', 'name', 'a']], {}])
    end
  end

  context 'when measuring length' do
    let(:response) { [3] }

    it 'returns the number' do
      expect(users.len).to eq(3)
      expect(transport.last).to have_attributes(function: 'crud.len', arguments: ['users', {}])
    end
  end

  context 'when truncating' do
    let(:response) { [true] }

    it 'returns true' do
      expect(users.truncate).to be(true)
      expect(transport.last).to have_attributes(function: 'crud.truncate', arguments: ['users', {}])
    end
  end
end
