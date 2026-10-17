# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Defaults do
  subject(:defaults) do
    described_class.new(read: { mode: 'read', prefer_replica: true, balance: true, timeout: 2 },
                        write: { noreturn: true, stop_on_error: true, timeout: 3 })
  end

  it 'gives read functions the read defaults' do
    expect(defaults.options_for('select')).to eq(mode: 'read', prefer_replica: true, balance: true, timeout: 2)
  end

  it 'drops the read defaults min and max do not accept' do
    expect(defaults.options_for('min')).to eq(mode: 'read', timeout: 2)
    expect(defaults.options_for('max')).to eq(mode: 'read', timeout: 2)
  end

  it 'gives write functions the write defaults they accept' do
    expect(defaults.options_for('insert')).to eq(noreturn: true, timeout: 3)
    expect(defaults.options_for('insert_object_many')).to eq(noreturn: true, stop_on_error: true, timeout: 3)
  end

  it 'passes only the timeout to truncate, storage_info and schema' do
    expect(defaults.options_for('truncate')).to eq(timeout: 3)
    expect(defaults.options_for('storage_info')).to eq(timeout: 2)
    expect(defaults.options_for('schema')).to eq(timeout: 2)
  end
end
