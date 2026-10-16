# frozen_string_literal: true

RSpec.describe Tarantool::Client do
  let(:instrumenter) { RecordingInstrumenter.new }
  let!(:schema_state) { { orders: false } }
  let(:handler) do
    lambda do |request, fake|
      case request.body[0x10]
      when 281
        fake.reply(request, [[512, 1, 'users', 'memtx', 0, {}, [{ 'name' => 'id' }, { 'name' => 'key' }]],
                             *([[600, 1, 'orders']] if schema_state[:orders])])
      when 289 then fake.reply(request, [[512, 0, 'primary'], [512, 1, 'email']])
      else
        next fake.reply_error(request, code: 33, message: 'no such function') if request.body[0x22] == 'missing'

        fake.reply(request, [[1]])
      end
    end
  end
  let(:server) { FakeTarantool.new(check_schema_version: true, &handler) }
  let(:client) { described_class.new(server.uri, user: 'app', password: 'secret', instrumenter:) }

  after do
    client.close
    server.stop
  end

  def requests = instrumenter.payloads('request.tarantool')

  it 'emits one event for a select by name with space, index and address' do
    client.select(:users, ['secret'], index: :email)

    expect(requests).to eq([{ space: :users, index: :email, address: server.path, request: :select }])
  end

  it 'reports numeric ids as passed and leaves the index out of an insert' do
    client.select(512, 1, index: 0)
    client.insert(:users, [1, 'secret'])

    expect(requests).to eq([{ space: 512, index: 0, address: server.path, request: :select },
                            { space: :users, address: server.path, request: :insert }])
  end

  it 'emits one event for an insert resolved by format even with a numeric space id' do
    client.insert(512, { id: 1, key: 'secret' })

    expect(requests).to eq([{ space: 512, address: server.path, request: :insert }])
  end

  it 'names the function of a call and reports SQL text without its values' do
    client.call('f', ['secret'])
    client.execute('SELECT ?', ['secret'])

    expect(requests).to eq([{ request: :call, function: 'f', address: server.path },
                            { request: :execute, sql: 'SELECT ?', address: server.path }])
  end

  it 'adds the exception keys for a failed request' do
    expect { client.call('missing') }.to raise_error(Tarantool::ServerError)

    expect(requests.first).to include(exception: ['Tarantool::ServerError', a_string_including('no such function')],
                                      exception_object: an_instance_of(Tarantool::ServerError))
  end

  it 'marks a request whose unknown name made the schema reload' do
    client
    schema_state[:orders] = true
    client.select(:orders, 1)

    expect(requests.last).to include(space: :orders, schema_reloaded: true)
  end

  it 'marks a request retried after a schema version error, in one event' do
    client
    server.schema_version = 2
    client.select(:users, 1)

    expect(requests).to eq([{ space: :users, index: 0, address: server.path, request: :select, schema_reloaded: true }])
  end

  it 'emits begin, the operations and commit of a transaction' do
    skip 'Task 7'

    client.transaction { |tx| tx.select(:users, 1) }

    expect(requests.map { |payload| payload[:request] }).to eq(%i[begin select commit])
  end

  it 'emits rollback when the transaction block raises' do
    skip 'Task 7'

    expect { client.transaction { raise 'boom' } }.to raise_error('boom')

    expect(requests.map { |payload| payload[:request] }).to eq(%i[begin rollback])
  end
end
