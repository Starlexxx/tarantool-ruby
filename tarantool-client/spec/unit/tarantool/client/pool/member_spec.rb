# frozen_string_literal: true

RSpec.describe Tarantool::Client::Pool::Member do
  subject(:member) { described_class.new(server.uri, { reconnect_delay: 0.01 }) }

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

    expect(Thread.list.none? { |thread| thread.name&.start_with?('tarantool-pool') && thread.alive? }).to be(true)
  end

  it 'shows only the address' do
    expect(member.address).to eq(server.path)
  end
end
