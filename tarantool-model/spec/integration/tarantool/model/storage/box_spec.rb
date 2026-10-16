# frozen_string_literal: true

RSpec.describe Tarantool::Model::Storage::Box, :integration do
  subject(:storage) { described_class.new(client) }

  let(:client) { Tarantool::Client.new(ENV.fetch('TARANTOOL_MODEL_URI', 'tcp://app:secret@localhost:3321')) }

  before { client.eval('box.space.users:truncate() box.space.accounts:truncate()') }
  after { client.close }

  it_behaves_like 'a model storage', count: false
  it_behaves_like 'a box-compatible storage'

  it 'raises NotSupportedError for count' do
    expect { storage.count(:users, index: nil, key: [], iterator: :all) }
      .to raise_error(Tarantool::Model::NotSupportedError)
  end

  it 'works over a Pool with read and write modes' do
    pool = Tarantool::Client::Pool.new([ENV.fetch('TARANTOOL_MODEL_URI', 'tcp://app:secret@localhost:3321')])
    box = described_class.new(pool, read: { mode: :any }, write: { mode: :rw })
    box.insert(:users, { id: 1, email: 'a', age: 1 })

    expect(box.get(:users, [1]).attributes).to include(email: 'a')
  ensure
    pool&.close
  end
end
