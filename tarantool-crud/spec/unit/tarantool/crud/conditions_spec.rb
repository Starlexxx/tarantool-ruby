# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Conditions do
  def build(conditions) = described_class.build(conditions)

  it 'keeps nil, which selects every row' do
    expect(build(nil)).to be_nil
  end

  it 'turns a Hash value into equality' do
    expect(build({ age: 18 })).to eq([['==', 'age', 18]])
  end

  it 'turns ranges into bounds' do
    expect(build({ age: 18..65 })).to eq([['>=', 'age', 18], ['<=', 'age', 65]])
    expect(build({ age: 18...65 })).to eq([['>=', 'age', 18], ['<', 'age', 65]])
  end

  it 'turns open ranges into one bound' do
    expect(build({ age: 18.. })).to eq([['>=', 'age', 18]])
    expect(build({ age: ..65 })).to eq([['<=', 'age', 65]])
    expect(build({ age: ...65 })).to eq([['<', 'age', 65]])
  end

  it 'joins several Hash keys' do
    expect(build({ name: 'a', age: 18.. })).to eq([['==', 'name', 'a'], ['>=', 'age', 18]])
  end

  it 'converts symbols in Array conditions to strings' do
    expect(build([[:>=, :age, 18], ['==', 'name', :a]])).to eq([['>=', 'age', 18], ['==', 'name', :a]])
  end

  it 'rejects unknown operators' do
    expect { build([[:~, :age, 1]]) }.to raise_error(ArgumentError, 'unknown condition operator: ~')
  end
end
