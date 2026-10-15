# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Call do
  subject(:crud_call) { described_class.new(transport, defaults:, timeout_margin: 0.5) }

  let(:defaults) { Tarantool::Crud::Defaults.new(read: { mode: 'read', timeout: 2 }, write: {}) }
  let(:transport) { FakeCaller.new(response) }
  let(:response) { [crud_result([1, 'a']), nil] }

  it 'calls the crud function with defaults merged under call options' do
    crud_call.value('get', ['users', 1], { timeout: 4 })

    expect(transport.last).to have_attributes(function: 'crud.get',
                                              arguments: ['users', 1, { mode: 'read', timeout: 4 }])
  end

  it 'adds the margin to the transport timeout' do
    crud_call.value('get', ['users', 1], { timeout: 4 })

    expect(transport.last.timeout).to eq(4.5)
  end

  it 'leaves the transport timeout to the caller without a crud timeout' do
    crud_call.value('insert', ['users', [1, 'a']], {})

    expect(transport.last.timeout).to be_nil
  end

  it 'returns the crud result' do
    expect(crud_call.value('get', ['users', 1], {})).to eq(crud_result([1, 'a']))
  end

  context 'when the response has no error element' do
    let(:response) { [3] }

    it 'returns the result' do
      expect(crud_call.value('len', ['users'], {})).to eq(3)
    end
  end

  context 'when crud returns an error' do
    let(:response) { [nil, crud_error('GetError', 'Space "users" doesn\'t exist')] }

    it 'raises the mapped error' do
      expect { crud_call.value('get', ['users', 1], {}) }
        .to raise_error(Tarantool::Crud::GetError, 'Space "users" doesn\'t exist')
    end
  end

  context 'when a *_many call returns errors' do
    let(:response) { [crud_result([1, 'a']), [crud_error('CallError', 'dup')]] }

    it 'returns them in a ManyResult' do
      result = crud_call.many('insert_many', ['users', [[1, 'a'], [1, 'a']]], {})

      expect(result).to have_attributes(to_a: [{ id: 1, name: 'a' }], errors: [an_instance_of(Tarantool::Crud::CallError)])
    end
  end
end
