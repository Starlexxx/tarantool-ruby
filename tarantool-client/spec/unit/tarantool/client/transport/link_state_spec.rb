# frozen_string_literal: true

RSpec.describe Tarantool::Client::Transport::LinkState do
  subject(:state) { described_class.new('tcp://localhost:3301', reconnect: false) }

  let(:connection) { instance_double(Tarantool::Client::Transport::Connection) }

  before do
    state.attempting(connection)
    state.install(connection)
  end

  it 'claims the loss of the current connection once' do
    expect(state.claim_loss(connection)).to be(true)
    expect(state.claim_loss(connection)).to be(false)
  end

  it 'does not claim the loss of a connection that is not current' do
    other = instance_double(Tarantool::Client::Transport::Connection)

    expect(state.claim_loss(other)).to be(false)
  end
end
