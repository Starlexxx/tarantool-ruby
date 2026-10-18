# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Privileges do
  it 'normalizes names into mask order' do
    expect(described_class.check(%i[write read], 'grant app')).to eq(%w[read write])
    expect(described_class.check(:alter, 'grant app')).to eq(%w[alter])
  end

  it 'rejects an unknown privilege' do
    expect { described_class.check(%i[read execute], 'grant app') }
      .to raise_error(ArgumentError, 'grant app: unknown privilege :execute; allowed: read, write, usage, create, ' \
                                     'drop, alter, trigger, insert, update, delete')
  end

  it 'rejects an empty list' do
    expect { described_class.check([], 'grant app') }.to raise_error(ArgumentError, 'grant app: no privileges')
  end

  it 'decodes a mask, leaving out bits it does not know' do
    expect(described_class.names(3)).to eq(%w[read write])
    expect(described_class.names(7927)).to eq(%w[read write usage create drop alter trigger insert update delete])
    expect(described_class.names(4)).to eq([])
  end
end
