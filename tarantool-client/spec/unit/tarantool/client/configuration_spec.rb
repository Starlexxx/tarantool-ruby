# frozen_string_literal: true

RSpec.describe Tarantool::Client::Configuration do
  describe '.build' do
    it 'uses defaults without arguments' do
      expect(described_class.build).to have_attributes(
        host: 'localhost', port: 3301, path: nil, user: nil, connect_timeout: 3, request_timeout: 10
      )
    end

    it 'parses a tcp URI with escaped credentials' do
      expect(described_class.build('tcp://app:s%40cret@db.local:3302')).to have_attributes(
        host: 'db.local', port: 3302, user: 'app', password: 's@cret'
      )
    end

    it 'accepts host:port without a scheme' do
      expect(described_class.build('db.local:3305')).to have_attributes(host: 'db.local', port: 3305)
    end

    it 'parses a unix socket URI' do
      expect(described_class.build('unix:/tmp/tt.sock').path).to eq('/tmp/tt.sock')
    end

    it 'lets options override the URI' do
      expect(described_class.build('tcp://app@db.local', user: 'admin').user).to eq('admin')
    end

    it 'rejects unknown options' do
      expect { described_class.build(retries: 3) }.to raise_error(ArgumentError)
    end
  end

  describe '#address' do
    it 'is host:port for tcp' do
      expect(described_class.build('db.local:3302').address).to eq('db.local:3302')
    end

    it 'is the path for unix sockets' do
      expect(described_class.build('unix:/tmp/tt.sock').address).to eq('/tmp/tt.sock')
    end
  end
end
