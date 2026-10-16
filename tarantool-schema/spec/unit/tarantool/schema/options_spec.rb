# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Options do
  it 'passes known keys' do
    expect(described_class.check({ name: :id }, %i[name type], 'field id')).to be_nil
  end

  it 'names every unsupported key' do
    expect { described_class.check({ name: :c, is_sync: true, temporary: true }, %i[name], 'space codes') }
      .to raise_error(ArgumentError, 'space codes: unsupported :is_sync, :temporary')
  end

  it 'returns a boolean as is' do
    expect(described_class.boolean(false, 'index pk unique')).to be(false)
  end

  it 'rejects anything but true or false' do
    expect { described_class.boolean('yes', 'index pk unique') }
      .to raise_error(ArgumentError, 'index pk unique: expected true or false, got "yes"')
  end
end
