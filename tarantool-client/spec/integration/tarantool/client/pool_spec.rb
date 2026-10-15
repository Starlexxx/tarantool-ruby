# frozen_string_literal: true

RSpec.describe Tarantool::Client::Pool, :failover do
  subject(:pool) { described_class.new(uris, reconnect_delay: 0.1) }

  let(:uris) { ENV.fetch('TARANTOOL_FAILOVER_URIS').split(',') }
  let(:admins) { uris.map { |uri| Tarantool::Client.new(uri) } }

  before { set_read_only(false, true) }

  after do
    pool.close
    set_read_only(false, false)
    admins.each(&:close)
  end

  def set_read_only(*flags)
    admins.zip(flags) { |admin, flag| admin.eval('box.cfg{read_only = ...}', [flag]) }
  end

  def uuid(index) = admins[index].eval('return box.info.uuid').first

  def uuid_for(mode)
    pool.eval('return box.info.uuid', mode:).first
  rescue Tarantool::NoAvailableInstanceError
    nil
  end

  it 'sends :rw requests to the writable instance and :ro to the read-only one' do
    expect([uuid_for(:rw), uuid_for(:ro)]).to eq([uuid(0), uuid(1)])
  end

  it 'moves :rw to the other instance after a switchover' do
    pool
    set_read_only(true, false)

    switched = [uuid(1), uuid(0)]
    wait_for(timeout: 5) { [uuid_for(:rw), uuid_for(:ro)] == switched }
    expect([uuid_for(:rw), uuid_for(:ro)]).to eq(switched)
  end

  it 'runs transactions on the writable instance' do
    expect(pool.transaction { |tx| tx.eval('return box.info.uuid') }.first).to eq(uuid(0))
  end
end
