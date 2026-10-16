# frozen_string_literal: true

RSpec.describe Tarantool::Model::Transactions do
  let(:storage) { Object.new }
  let(:other) { Object.new }

  it 'exposes the handle of an open transaction and drops it afterwards' do
    inside = described_class.open(storage, :tx) { described_class.handle(storage) }

    expect([inside, described_class.handle(storage)]).to eq([:tx, nil])
  end

  it 'drops the handle when the block raises' do
    expect { described_class.open(storage, :tx) { raise 'boom' } }.to raise_error('boom')
    expect(described_class.handle(storage)).to be_nil
  end

  it 'allows writes outside transactions and through the storage of the open one' do
    expect { described_class.check_write!(storage) }.not_to raise_error
    expect { described_class.open(storage, :tx) { described_class.check_write!(storage) } }.not_to raise_error
  end

  it 'rejects a write through another storage while a transaction is open' do
    expect { described_class.open(storage, :tx) { described_class.check_write!(other) } }
      .to raise_error(Tarantool::Model::TransactionMismatchError, /one storage instance/)
  end

  it 'is local to the fiber' do
    seen = described_class.open(storage, :tx) { Fiber.new { described_class.handle(storage) }.resume }

    expect(seen).to be_nil
  end
end
