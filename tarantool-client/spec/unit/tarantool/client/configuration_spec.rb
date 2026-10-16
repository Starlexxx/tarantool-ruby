# frozen_string_literal: true

require 'pp'

RSpec.describe Tarantool::Client::Configuration do
  describe '.build' do
    it 'uses defaults without arguments' do
      expect(described_class.build).to have_attributes(
        host: 'localhost', port: 3301, path: nil, user: nil, connect_timeout: 3, request_timeout: 10
      )
    end

    it 'enables reconnect with backoff by default' do
      expect(described_class.build).to have_attributes(
        reconnect: true, reconnect_attempts: Float::INFINITY, reconnect_delay: 0.1, reconnect_max_delay: 5
      )
    end

    it 'defaults max_frame_size to 64 MB' do
      expect(described_class.build.max_frame_size).to eq(64 * 1024 * 1024)
    end

    it 'accepts a custom max_frame_size' do
      expect(described_class.build(max_frame_size: 1024).max_frame_size).to eq(1024)
    end

    it 'takes reconnect options' do
      expect(described_class.build(reconnect: false, reconnect_attempts: 3)).to have_attributes(
        reconnect: false, reconnect_attempts: 3
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

    it 'parses a unix socket URI with three slashes' do
      expect(described_class.build('unix:///tmp/tt.sock').path).to eq('/tmp/tt.sock')
    end

    it 'parses a tarantool-style unix socket URI' do
      expect(described_class.build('unix/:/tmp/tt.sock').path).to eq('/tmp/tt.sock')
    end

    it 'keeps a relative unix socket path relative' do
      expect(described_class.build('unix:tt.sock').path).to eq('tt.sock')
    end

    it 'rejects a bare unix URI' do
      expect { described_class.build('unix:') }.to raise_error(ArgumentError, 'invalid Tarantool URI')
    end

    it 'rejects a unix URI with no path' do
      expect { described_class.build('unix://') }.to raise_error(ArgumentError, 'invalid Tarantool URI')
    end

    it 'parses an IPv6 host without a scheme' do
      expect(described_class.build('[::1]:3301')).to have_attributes(host: '::1', port: 3301)
    end

    it 'parses an IPv6 host with a tcp scheme' do
      expect(described_class.build('tcp://[::1]:3302')).to have_attributes(host: '::1', port: 3302)
    end

    it 'treats an empty URI user as nil' do
      expect(described_class.build('tcp://:pw@h:1').user).to be_nil
    end

    it 'lets options override the URI' do
      expect(described_class.build('tcp://app@db.local', user: 'admin').user).to eq('admin')
    end

    it 'rejects unknown options' do
      expect { described_class.build(retries: 3) }.to raise_error(ArgumentError)
    end

    it 'rejects an invalid URI' do
      expect { described_class.build('tcp://u:p#x@h:1') }.to raise_error(ArgumentError, 'invalid Tarantool URI')
    end
  end

  describe '#address' do
    it 'is host:port for tcp' do
      expect(described_class.build('db.local:3302').address).to eq('db.local:3302')
    end

    it 'is the path for unix sockets' do
      expect(described_class.build('unix:/tmp/tt.sock').address).to eq('/tmp/tt.sock')
    end

    it 'brackets an IPv6 host' do
      expect(described_class.build('[::1]:3301').address).to eq('[::1]:3301')
    end
  end

  describe '#to_h' do
    it 'keeps the password' do
      expect(described_class.build('tcp://app:secret@db.local').to_h[:password]).to eq('secret')
    end

    it 'builds the same configuration again' do
      config = described_class.build('tcp://app:secret@db.local', request_timeout: 2)

      expect(described_class.build(**config.to_h)).to eq(config)
    end
  end

  describe '#inspect' do
    it 'masks a password' do
      expect(described_class.build('tcp://app:secret@db.local').inspect).to include('password="[FILTERED]"')
    end

    it 'keeps a nil password as nil' do
      expect(described_class.build.inspect).to include('password=nil')
    end
  end

  describe '#to_s' do
    it 'matches inspect' do
      config = described_class.build('tcp://app:secret@db.local')
      expect(config.to_s).to eq(config.inspect)
    end
  end

  describe '#pretty_print' do
    it 'masks the password' do
      config = described_class.build('tcp://app:secret@db.local')
      output = PP.pp(config, +'')
      expect(output).to include('[FILTERED]')
      expect(output).not_to include('secret')
    end
  end
end
