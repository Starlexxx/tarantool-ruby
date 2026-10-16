# frozen_string_literal: true

RSpec.describe Tarantool::Client::Pool::Member do
  subject(:member) { described_class.new(server.uri, { reconnect_delay: 0.01, reconnect_max_delay: 0.05 }) }

  let(:roles) { { 'a' => true } }
  let(:server) { status_server('a', roles) }

  after do
    member.close
    server.stop
  end

  it 'reports the role from box.status once started' do
    expect(member.start).to be_nil
    expect(member.read_only).to be(true)
  end

  it 'follows role changes' do
    member.start
    change_role(server, roles, 'a', false)

    wait_for { member.read_only == false }
    expect(member.read_only).to be(false)
  end

  context 'with an instrumenter' do
    subject(:member) { described_class.new(server.uri, { reconnect_delay: 0.01, instrumenter: }) }

    let(:instrumenter) { RecordingInstrumenter.new }

    def roles_reported = instrumenter.payloads('role_change.tarantool')

    it 'reports nothing for the first role' do
      member.start
      wait_for { member.read_only == true }

      expect(roles_reported).to eq([])
    end

    it 'reports a change, not the repeated value reported alongside it' do
      member.start
      change_role(server, roles, 'a', true)
      change_role(server, roles, 'a', false)
      wait_for { roles_reported.any? }

      expect(roles_reported).to eq([{ read_only: false, address: server.path }])
    end

    it 'reports nothing for a reconnect that brings back the same role' do
      member.start
      server.refusing = true
      server.disconnect
      wait_for { member.read_only.nil? }
      server.refusing = false

      wait_for { member.read_only == true }
      expect(roles_reported).to eq([])
    end
  end

  it 'gives access to its client' do
    member.start

    expect(member.client.eval('return 1')).to eq(['a'])
  end

  it 'has no role while its instance is unreachable' do
    member.start
    server.refusing = true
    server.disconnect

    wait_for { member.read_only.nil? }
    expect(member.read_only).to be_nil
  end

  it 'returns the connect error and keeps connecting in the background' do
    server.refusing = true

    expect(member.start).to be_a(Tarantool::ConnectionError)
    server.refusing = false
    wait_for { member.read_only == true }
    expect(member.client).to be_a(Tarantool::Client)
  end

  it 'stops connecting in the background on close' do
    server.refusing = true
    member.start
    member.close

    expect(leftover_threads).to be_empty
  end

  it 'keeps connecting in the background after an unexpected error' do
    server.refusing = true
    member.start
    expect do
      allow(Tarantool::Client).to receive(:new).and_wrap_original do |original, *args, **options|
        next original.call(*args, **options) unless server.refusing

        server.refusing = false
        raise 'boom'
      end
      wait_for { member.read_only == true }
    end.to output(/RuntimeError: boom/).to_stderr
  end

  it 'reports an unexpected connect error to the logger when one is set' do
    output = StringIO.new
    logged = described_class.new(server.uri, { reconnect_delay: 0.01, logger: Logger.new(output) })
    server.refusing = true
    logged.start
    allow(Tarantool::Client).to receive(:new).and_raise(RuntimeError, 'boom')
    server.refusing = false

    wait_for { output.string.include?('RuntimeError: boom') }
    expect(output.string).to include('RuntimeError: boom')
    logged.close
  end

  it 'forgets the role while disconnected and takes the new one after reconnecting' do
    member.start
    server.refusing = true
    server.disconnect
    wait_for { member.read_only.nil? }
    roles['a'] = false
    server.refusing = false

    wait_for { !member.read_only.nil? }
    expect(member.read_only).to be(false)
  end

  context 'when a new connection reports its role late' do
    let(:late) { Thread::Queue.new }
    let(:server) do
      announced = {}
      FakeTarantool.new do |request, fake|
        next fake.reply(request, []) unless request.type == 0x4a && !announced[fake.connections]

        announced[fake.connections] = true
        late.pop if fake.connections > 1
        fake.event('box.status', { 'is_ro' => roles['a'] })
      end
    end

    it 'forgets the old role on reconnect even if nobody asked for it meanwhile' do
      member.start
      client = member.client
      roles['a'] = false
      server.disconnect
      wait_for { server.connections == 2 && client.connected? }

      expect(member.read_only).to be_nil
      late << true
      wait_for { member.read_only == false }
    end

    it 'forgets the old role on reconnect while the watcher dispatcher is busy' do
      member.start
      busy = Thread::Queue.new
      member.client.instance_variable_get(:@watchers).defer { busy.pop(timeout: 2) }
      server.disconnect
      wait_for { server.connections == 2 && member.client.connected? }

      expect(member.read_only).to be_nil
    ensure
      busy << true
      late << true
    end
  end

  it 'stops waiting for box.status when closed during start' do
    silent = FakeTarantool.new { |request, fake| fake.reply(request, []) }
    member = described_class.new(silent.uri, { connect_timeout: 5 })
    Thread.new { sleep 0.05 until member.client && member.close }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    member.start
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
  ensure
    silent.stop
  end

  it 'shows only the address' do
    expect(member.address).to eq(server.path)
  end

  it 'keeps credentials out of inspect' do
    member = described_class.new(server.uri, { user: 'app', password: 'secret' })

    expect(member.inspect).to eq("#<Tarantool::Client::Pool::Member #{server.path}>")
  end

  it 'passes the real password to Client.new, not [FILTERED]' do
    seen_password = nil
    allow(Tarantool::Client).to receive(:new).and_wrap_original do |original, *args, **opts|
      seen_password = opts[:password]
      original.call(*args, **opts)
    end
    member = described_class.new(server.uri, { user: 'app', password: 'secret' })

    member.start

    expect(seen_password).to eq('secret')
  ensure
    member&.close
  end

  describe '#reset_for_fork' do
    it 'survives an inherited retry thread that died with an exception' do
      retrier = Thread.new { raise NotImplementedError, 'died' }.tap { |thread| thread.report_on_exception = false }
      wait_for { !retrier.alive? }
      member.instance_variable_set(:@retrier, retrier)

      expect { member.reset_for_fork }.not_to raise_error
    end

    it 'survives an inherited client that fails to close' do
      client = instance_double(Tarantool::Client)
      allow(client).to receive(:close).and_raise(Tarantool::ConnectionError, 'gone')
      member.instance_variable_set(:@client, client)

      expect { member.reset_for_fork }.not_to raise_error
    end
  end
end
