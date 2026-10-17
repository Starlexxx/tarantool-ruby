# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Alter do
  it 'accepts the allowed changes as Symbols or Strings' do
    expect(described_class.check(['add_field'])).to eq([:add_field])
  end

  it 'accepts nothing' do
    expect(described_class.check([])).to eq([])
  end

  it 'rejects anything else, naming what is allowed' do
    expect { described_class.check(%i[add_field drop]) }
      .to raise_error(ArgumentError, 'alter: unknown :drop; allowed: add_field')
  end
end
