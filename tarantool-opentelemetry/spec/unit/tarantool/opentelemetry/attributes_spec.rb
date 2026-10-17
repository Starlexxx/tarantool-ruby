# frozen_string_literal: true

RSpec.describe Tarantool::OpenTelemetry::Attributes do
  describe '.name' do
    def name(payload) = described_class.name('request.tarantool', payload)

    it 'names a space request after the request and the space' do
      expect(name({ request: :select, space: :users })).to eq('tarantool.select users')
    end

    it 'names a call after the function' do
      expect(name({ request: :call, function: 'crud.get' })).to eq('tarantool.call crud.get')
    end

    it 'names requests without a space or function after the request alone' do
      names = [{ request: :execute, sql: 'SELECT 1' }, { request: :ping }].map { |payload| name(payload) }

      expect(names).to eq(['tarantool.execute', 'tarantool.ping'])
    end

    it 'is just tarantool when the request was never built' do
      expect(name({ address: 'db:3301' })).to eq('tarantool')
    end

    it 'names lifecycle events after the event' do
      expect(described_class.name('role_change.tarantool', { read_only: true })).to eq('tarantool.role_change')
    end
  end

  describe '.for' do
    def attributes(payload, event: 'request.tarantool', **options)
      described_class.for(event, payload, db_statement: :omit, **options)
    end

    it 'describes a space request' do
      payload = { request: :select, space: :users, index: 'email', address: 'db1:3301', schema_reloaded: true }

      expect(attributes(payload)).to eq(
        'db.system' => 'tarantool', 'db.operation' => 'select', 'db.tarantool.space' => 'users',
        'db.tarantool.index' => 'email', 'db.tarantool.schema_reloaded' => true,
        'server.address' => 'db1', 'server.port' => 3301
      )
    end

    it 'keeps numeric space and index ids as Integers' do
      expect(attributes({ request: :delete, space: 512, index: 0 }))
        .to include('db.tarantool.space' => 512, 'db.tarantool.index' => 0)
    end

    it 'describes a call and a prepared statement' do
      call = attributes({ request: :call, function: 'crud.get' })
      prepared = attributes({ request: :execute, statement_id: 4 })

      expect(call).to include('db.tarantool.function' => 'crud.get')
      expect(prepared).to include('db.tarantool.statement_id' => 4)
      expect(prepared).not_to have_key('db.statement')
    end

    it 'omits the SQL text by default and includes it on request' do
      payload = { request: :execute, sql: 'SELECT 1' }

      expect(attributes(payload)).not_to have_key('db.statement')
      expect(attributes(payload, db_statement: :include)).to include('db.statement' => 'SELECT 1')
    end

    it 'leaves absent keys out and has db.system even without a request' do
      expect(attributes({ address: 'db1:3301' })).to eq('db.system' => 'tarantool', 'server.address' => 'db1',
                                                        'server.port' => 3301)
    end

    it 'splits an IPv6 address and keeps a unix socket path whole' do
      ipv6 = attributes({ request: :ping, address: '[::1]:3301' })
      unix = attributes({ request: :ping, address: '/var/run/tarantool.sock' })

      expect(ipv6).to include('server.address' => '::1', 'server.port' => 3301)
      expect(unix).to eq('db.system' => 'tarantool', 'db.operation' => 'ping',
                         'server.address' => '/var/run/tarantool.sock')
    end

    it 'describes lifecycle events with their own keys' do
      expect(attributes({ address: 'db1:3301', reason: 'EOF' }, event: 'disconnect.tarantool'))
        .to eq('db.system' => 'tarantool', 'server.address' => 'db1', 'server.port' => 3301,
               'tarantool.reason' => 'EOF')
      expect(attributes({ attempts: 3 }, event: 'reconnect.tarantool')).to include('tarantool.attempts' => 3)
      expect(attributes({ pending: 2 }, event: 'shutdown.tarantool')).to include('tarantool.pending' => 2)
    end

    it 'describes a role change and a failed reconnect without the exception keys' do
      role = attributes({ read_only: false }, event: 'role_change.tarantool')
      failed = attributes({ attempts: 5, exception: ['Tarantool::ConnectionError', 'refused'] },
                          event: 'reconnect_failed.tarantool')

      expect(role).to include('tarantool.read_only' => false)
      expect(failed).to eq('db.system' => 'tarantool', 'tarantool.attempts' => 5)
    end
  end
end
