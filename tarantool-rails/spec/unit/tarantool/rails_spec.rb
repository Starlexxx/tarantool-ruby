# frozen_string_literal: true

RSpec.describe Tarantool::Rails do
  let(:pool) { instance_double(Tarantool::Client::Pool, close: nil) }
  let(:config) do
    Tarantool::Rails::Configuration.from_hash(
      { addresses: ['tcp://localhost:3301'], user: 'app', password: 'secret', read: { mode: 'prefer_ro' },
        write: { mode: 'rw' }, admin_uri: 'tcp://app:secret@localhost:3301' }
    )
  end

  before do
    described_class.disconnect!
    described_class.config = config
    allow(Tarantool::Client::Pool).to receive(:new).and_return(pool)
    allow(pool).to receive(:is_a?).with(Tarantool::Client::Pool).and_return(true)
  end

  after do
    described_class.disconnect!
    described_class.config = Tarantool::Rails::Configuration.from_hash(Dummy::Application.config_for(:tarantool))
  end

  it 'has a version' do
    expect(Tarantool::Rails::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  describe '.pool' do
    it 'builds one pool from the addresses, client options and the Rails instrumenter' do
      2.times { described_class.pool }

      expect(Tarantool::Client::Pool).to have_received(:new)
        .with(['tcp://localhost:3301'], user: 'app', password: 'secret', instrumenter: ActiveSupport::Notifications)
        .once
    end

    it 'raises without a configuration' do
      described_class.config = nil

      expect { described_class.pool }.to raise_error(Tarantool::Rails::Error, /config/)
    end
  end

  describe '.storage' do
    it 'is a Storage::Box over the pool with the read and write options' do
      storage = described_class.storage
      allow(pool).to receive(:select).and_return([])

      storage.get(:users, [1])
      expect(storage).to be_a(Tarantool::Model::Storage::Box)
      expect(pool).to have_received(:select).with(:users, [1], limit: 1, as: :row, mode: :prefer_ro)
    end

    it 'is built once' do
      first = described_class.storage

      expect(described_class.storage).to be(first)
    end

    context 'with storage: crud' do
      let(:config) do
        Tarantool::Rails::Configuration.from_hash(
          { addresses: ['tcp://localhost:3301'], storage: 'crud',
            crud: { primary_index: 'pk', read: { mode: 'read' }, timeout_margin: 1 } }
        )
      end

      before { require 'tarantool/crud' }

      it 'is a Storage::Crud over a crud client on the pool' do
        crud = instance_double(Tarantool::Crud::Client)
        allow(Tarantool::Crud::Client).to receive(:new).and_return(crud)
        allow(Tarantool::Model::Storage::Crud).to receive(:new).and_call_original

        expect(described_class.storage).to be_a(Tarantool::Model::Storage::Crud)
        expect(Tarantool::Crud::Client).to have_received(:new).with(pool, read: { mode: 'read' }, timeout_margin: 1)
        expect(Tarantool::Model::Storage::Crud).to have_received(:new).with(crud, primary_index: :pk)
      end

      it 'raises a clear error when tarantool-crud is missing' do
        allow(described_class).to receive(:require).with('tarantool/crud').and_raise(LoadError)

        expect { described_class.storage }.to raise_error(Tarantool::Rails::Error, /tarantool-crud/)
      end
    end
  end

  describe '.disconnect!' do
    it 'closes the pool and builds a new one next time' do
      described_class.pool
      described_class.storage

      described_class.disconnect!
      described_class.pool

      expect(pool).to have_received(:close)
      expect(Tarantool::Client::Pool).to have_received(:new).twice
    end
  end

  describe '.schema' do
    let(:schema_path) { Dummy::Application.root.join('config/tarantool_schema.rb') }

    before do
      described_class.schema = nil
      described_class.schema_path = schema_path
    end

    it 'loads the schema file once' do
      allow(described_class).to receive(:load).and_call_original

      first = described_class.schema

      expect(first).to be_a(Tarantool::Schema::Definition)
      expect(described_class.schema).to be(first)
      expect(described_class).to have_received(:load).at_most(:once)
    end

    it 'raises for a file that does not assign the schema' do
      path = File.join(Dir.mktmpdir, 'tarantool_schema.rb')
      File.write(path, "1 + 1\n")
      described_class.schema_path = path

      expect { described_class.schema }.to raise_error(Tarantool::Rails::Error, "#{path} must assign Tarantool::Rails.schema")
    end
  end

  describe '.admin_client' do
    let(:client) { instance_double(Tarantool::Client, close: nil) }

    before { allow(Tarantool::Client).to receive(:new).and_return(client) }

    it 'yields a client on admin_uri and closes it' do
      expect(described_class.admin_client { |c| c }).to be(client)
      expect(Tarantool::Client).to have_received(:new).with('tcp://app:secret@localhost:3301')
      expect(client).to have_received(:close)
    end

    it 'closes the client when the block raises' do
      expect { described_class.admin_client { raise 'boom' } }.to raise_error('boom')
      expect(client).to have_received(:close)
    end

    it 'raises without admin_uri' do
      described_class.config = Tarantool::Rails::Configuration.from_hash({ addresses: ['tcp://localhost:3301'] })

      expect { described_class.admin_client { nil } }.to raise_error(Tarantool::Rails::Error, /admin_uri/)
    end
  end
end
