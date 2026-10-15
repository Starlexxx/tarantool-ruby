# frozen_string_literal: true

RSpec.describe Tarantool::Client::Schema do
  subject(:schema) do
    described_class.new(
      version: 80,
      spaces: [[512, 1, 'users', 'memtx', 0, {}, []]],
      indexes: [[512, 0, 'primary', 'tree', {}, []], [512, 1, 'email', 'tree', {}, []]]
    )
  end

  describe '#resolve' do
    it 'resolves space and index names' do
      expect(schema.resolve(:users, 'email')).to eq([512, 1])
    end

    it 'passes numeric ids through without lookup' do
      expect(schema.resolve(999, 7)).to eq([999, 7])
    end

    it 'raises SchemaError for an unknown space' do
      expect { schema.resolve(:orders, 0) }.to raise_error(Tarantool::SchemaError, /space 'orders'/)
    end

    it 'raises SchemaError for an unknown index' do
      expect { schema.resolve(:users, :phone) }.to raise_error(Tarantool::SchemaError, /index 'phone'/)
    end
  end

  describe '.fetch' do
    it 'loads spaces and indexes through the connection' do
      connection = instance_double(Tarantool::Client::Transport::Connection)
      spaces = Tarantool::Client::Protocol::Response.new({ 0x00 => 0, 0x05 => 81 }, { 0x30 => [[512, 1, 'users']] })
      indexes = Tarantool::Client::Protocol::Response.new({ 0x00 => 0, 0x05 => 81 }, { 0x30 => [[512, 0, 'primary']] })
      allow(connection).to receive(:perform).and_return(spaces, indexes)

      fetched = described_class.fetch(connection, timeout: 1)

      expect(fetched.version).to eq(81)
      expect(fetched.resolve(:users, :primary)).to eq([512, 0])
    end
  end
end
