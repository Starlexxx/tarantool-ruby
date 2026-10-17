# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Client do
  subject(:crud) { described_class.new(transport, read: { mode: 'read', balance: true }) }

  let(:transport) { FakeCaller.new(response) }
  let(:response) { [{ 'uuid-1' => { 'status' => 'running', 'is_master' => true } }] }

  it 'returns a handle for a space' do
    expect(crud.space(:users)).to be_a(Tarantool::Crud::Space).and(have_attributes(name: 'users'))
  end

  it 'reads storage info with the read defaults it accepts' do
    expect(crud.storage_info(timeout: 1)).to eq('uuid-1' => { 'status' => 'running', 'is_master' => true })
    expect(transport.last).to have_attributes(function: 'crud.storage_info', arguments: [{ timeout: 1 }], timeout: 1.5)
  end

  describe '#schema' do
    let(:space) do
      { 'format' => [{ 'name' => 'id', 'type' => 'unsigned' }],
        'indexes' => { 0 => { 'id' => 0, 'name' => 'primary', 'type' => 'TREE', 'unique' => true,
                              'parts' => [{ 'fieldno' => 1, 'type' => 'unsigned', 'is_nullable' => false }] } } }
    end
    let(:response) { [{ 'customers' => space }] }

    it 'reads every space with the read defaults it accepts' do
      expect(crud.schema.keys).to eq([:customers])
      expect(transport.last).to have_attributes(function: 'crud.schema', arguments: [nil, {}])
    end

    it 'reads one space' do
      transport = FakeCaller.new([space])

      expect(described_class.new(transport).schema(:customers, timeout: 1)).to include(:format, :indexes)
      expect(transport.last.arguments).to eq(['customers', { timeout: 1 }])
    end

    it 'raises SchemaError for an unknown space' do
      transport = FakeCaller.new([nil, crud_error('SchemaError', 'Space "nope" doesn\'t exist')])

      expect { described_class.new(transport).schema(:nope) }.to raise_error(Tarantool::Crud::SchemaError, /nope/)
    end
  end

  describe '#stats' do
    let(:response) { [{ 'spaces' => {} }] }

    it 'reads stats of every space' do
      expect(crud.stats).to eq('spaces' => {})
      expect(transport.last).to have_attributes(function: 'crud.stats', arguments: [])
    end

    it 'reads stats of one space' do
      crud.stats(:users)

      expect(transport.last.arguments).to eq(['users'])
    end

    it 'bounds the call by the given timeout plus the margin without sending options' do
      crud.stats(:users, timeout: 2)

      expect(transport.last).to have_attributes(arguments: ['users'], timeout: 2.5)
    end

    it 'falls back to the read timeout default' do
      described_class.new(transport, read: { timeout: 3 }).stats

      expect(transport.last).to have_attributes(arguments: [], timeout: 3.5)
    end

    context 'when crud has no stats' do
      let(:response) { [[]] }

      it 'returns an empty Hash' do
        expect(crud.stats(:users)).to eq({})
      end
    end
  end
end
