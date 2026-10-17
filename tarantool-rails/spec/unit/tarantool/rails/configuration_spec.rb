# frozen_string_literal: true

RSpec.describe Tarantool::Rails::Configuration do
  def build(**options)
    described_class.from_hash({ addresses: ['tcp://localhost:3301'], **options })
  end

  it 'has defaults for everything but the addresses' do
    config = build

    expect(config.to_h).to eq(addresses: ['tcp://localhost:3301'], client_options: {}, storage: :box, read: {},
                              write: {}, crud: { primary_index: :primary }, admin_uri: nil)
  end

  it 'wraps a single address' do
    expect(described_class.from_hash({ address: 'tcp://localhost:3301' }).addresses).to eq(['tcp://localhost:3301'])
  end

  it 'requires addresses' do
    expect { described_class.from_hash({ user: 'app' }) }.to raise_error(ArgumentError, /addresses/)
  end

  it 'rejects an unknown key by name' do
    expect { build(timeout: 3) }.to raise_error(ArgumentError, 'unknown key timeout in config/tarantool.yml')
  end

  it 'collects the client options' do
    config = build(user: 'app', password: 'secret', connect_timeout: 1, request_timeout: 2, reconnect: false,
                   reconnect_attempts: 3, reconnect_delay: 0.5, reconnect_max_delay: 2, max_frame_size: 1024)

    expect(config.client_options).to eq(user: 'app', password: 'secret', connect_timeout: 1, request_timeout: 2,
                                        reconnect: false, reconnect_attempts: 3, reconnect_delay: 0.5,
                                        reconnect_max_delay: 2, max_frame_size: 1024)
  end

  it 'turns read and write modes into Symbols' do
    config = build(read: { mode: 'prefer_ro', timeout: 1 }, write: { mode: 'rw' })

    expect([config.read, config.write]).to eq([{ mode: :prefer_ro, timeout: 1 }, { mode: :rw }])
  end

  it 'takes the crud storage with its options' do
    config = build(storage: 'crud', crud: { primary_index: 'pk', read: { mode: 'read' }, timeout_margin: 1 })

    expect([config.storage, config.crud]).to eq([:crud, { primary_index: :pk, read: { mode: 'read' },
                                                          timeout_margin: 1 }])
  end

  it 'rejects an unknown storage' do
    expect { build(storage: 'memory') }.to raise_error(ArgumentError, /storage must be box or crud/)
  end

  it 'rejects an unknown crud key' do
    expect { build(crud: { bucket_id: 1 }) }.to raise_error(ArgumentError, 'unknown key bucket_id in crud')
  end

  it 'hides the password in inspect' do
    config = build(user: 'app', password: 'secret', admin_uri: 'tcp://app:secret@localhost:3301')

    expect(config.inspect).to include('[FILTERED]')
    expect(config.inspect).not_to include('secret')
  end
end
