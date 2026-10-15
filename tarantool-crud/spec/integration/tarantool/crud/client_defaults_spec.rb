# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Client, :integration do
  subject(:crud) do
    described_class.new(connection, read: { mode: 'read', prefer_replica: true, balance: true },
                                    write: { noreturn: true })
  end

  let(:connection) { Tarantool::Client.new(ENV.fetch('TARANTOOL_CRUD_URI', 'tcp://app:secret@localhost:3311')) }
  let(:customers) { crud.space(:customers) }

  before { customers.truncate }
  after { connection.close }

  it 'applies write defaults' do
    expect(customers.insert([1, nil, 'a', 20])).to be_nil
    expect(customers.get(1)).to include(name: 'a')
  end

  it 'applies read defaults only where crud accepts them' do
    customers.insert([1, nil, 'a', 20])

    expect(customers.min(:age_index)).to include(id: 1)
    expect(customers.len).to eq(1)
    expect(customers.count).to eq(1)
  end
end
