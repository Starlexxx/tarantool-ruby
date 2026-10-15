# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Result do
  subject(:result) { described_class.from_crud(crud_result([1, 'a'], [2, 'b'])) }

  it 'builds Hash rows from metadata' do
    expect(result.to_a).to eq([{ id: 1, name: 'a' }, { id: 2, name: 'b' }])
  end

  it 'keeps tuples and metadata' do
    expect(result).to have_attributes(
      tuples: [[1, 'a'], [2, 'b']],
      metadata: [{ name: 'id', type: 'any' }, { name: 'name', type: 'any' }]
    )
  end

  it 'answers first, last, size and empty?' do
    expect(result).to have_attributes(first: { id: 1, name: 'a' }, last: { id: 2, name: 'b' }, size: 2, empty?: false)
  end

  it 'treats a response without rows as empty' do
    expect(described_class.from_crud(crud_result.except('rows'))).to have_attributes(to_a: [], empty?: true)
  end

  it 'treats a nil response as empty' do
    expect(described_class.from_crud(nil)).to have_attributes(metadata: [], tuples: [], first: nil)
  end
end
