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
      allow(Tarantool::Client).to receive(:new).and_wrap_original do |original, **options|
        next original.call(**options) unless server.refusing

        server.refusing = false
        raise 'boom'
      end
      wait_for { member.read_only == true }
    end.to output(/RuntimeError: boom/).to_stderr
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
end
