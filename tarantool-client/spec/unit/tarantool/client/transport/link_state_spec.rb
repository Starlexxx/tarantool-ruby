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

  describe 'draining' do
    let(:other) { instance_double(Tarantool::Client::Transport::Connection) }

    before { allow(connection).to receive(:closed?).and_return(false) }

    it 'leaves ready for the current connection and runs the block once' do
      started = [state.start_draining(connection) { :drainer }, state.start_draining(connection) { :again }]

      expect([started, state.connected?]).to eq([[true, false], false])
    end

    it 'does not start for a connection that is not current' do
      expect(state.start_draining(other) { :drainer }).to be(false)
    end

    it 'makes requests wait while draining' do
      state.start_draining(connection) { :drainer }

      expect { state.current(Tarantool::Client::Transport::Deadline.after(0.01)) }
        .to raise_error(Tarantool::ConnectionError, /not connected/)
    end

    it 'hands the connection out again once draining is finished' do
      state.start_draining(connection) { :drainer }
      state.finish_draining(connection)

      expect([state.connected?, state.current(nil)]).to eq([true, connection])
    end

    it 'starts a reconnect from draining' do
      state.start_draining(connection) { :drainer }
      state.start_reconnect(connection) { :reconnector }

      expect(state.close).to eq([:reconnector, nil, :drainer])
    end

    it 'returns the drain thread from close' do
      state.start_draining(connection) { :drainer }

      expect(state.close).to eq([nil, nil, :drainer])
    end
  end
end
