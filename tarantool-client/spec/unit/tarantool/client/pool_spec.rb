# frozen_string_literal: true

RSpec.describe Tarantool::Client::Pool do
  it 'rejects an empty address list' do
    expect { described_class.new([]) }.to raise_error(ArgumentError, /at least one address/)
  end

  it 'raises NoAvailableInstanceError when no address answers' do
    down = FakeTarantool.new
    down.refusing = true

    expect { described_class.new([down.uri], reconnect_delay: 0.01) }
      .to raise_error(Tarantool::NoAvailableInstanceError, /cannot connect/)
    expect(leftover_threads).to be_empty
  ensure
    down.stop
  end

  context 'with a member that fails unexpectedly' do
    let(:silent) { FakeTarantool.new { |request, fake| fake.reply(request, []) } }
    let(:servers) { [status_server('rw', { 'rw' => false }), silent] }
    let(:members) { [] }

    before do
      allow(Tarantool::Client::Pool::Member).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { |member| members << member }
      end
    end

    after { servers.each(&:stop) }

    it 'waits for the other members to start before raising' do
      allow(Tarantool::Client).to receive(:new).and_wrap_original do |original, *args, **options|
        args.first&.include?(servers.first.path) ? raise('boom') : original.call(*args, **options)
      end

      expect { described_class.new(servers.map(&:uri), connect_timeout: 0.3) }.to raise_error('boom')
      expect(leftover_threads).to be_empty
    end

    it 'closes every member even if one fails to close' do
      pool = described_class.new(servers.map(&:uri), connect_timeout: 0.3)
      allow(members.first).to receive(:close).and_wrap_original do |original|
        original.call
        raise 'boom'
      end

      expect { pool.close }.to raise_error('boom')
      expect(members.map(&:client)).to all(satisfy { |client| !client.connected? })
    end
  end

  context 'with a member that has a schema' do
    let(:server) do
      announced = {}
      FakeTarantool.new do |request, fake|
        next announce(fake, announced, false) if request.type == 0x4a

        fake.reply(request, request.body[0x10] == 281 ? [[512, 1, 'users', 'memtx', 0, {}, []]] : [])
      end
    end
    let(:pool) { described_class.new([server.uri], reconnect_delay: 0.01) }

    after do
      pool.close
      server.stop
    end

    it 'returns space info from the instance picked by mode' do
      expect(pool.space_info(:users, mode: :rw).id).to eq(512)
    end
  end

  describe 'routing' do
    let(:roles) { { 'rw' => false, 'ro1' => true, 'ro2' => true } }
    let(:servers) { roles.keys.to_h { |name| [name, status_server(name, roles)] } }
    let(:pool) { described_class.new(servers.values.map(&:uri), reconnect_delay: 0.01) }

    after do
      pool.close
      servers.each_value(&:stop)
    end

    def served_by(mode, times) = Array.new(times) { pool.eval('return 1', mode:).first }

    it 'sends :rw requests to the writable instance' do
      expect(served_by(:rw, 3)).to eq(%w[rw rw rw])
    end

    it 'round-robins :ro requests among the read-only instances' do
      expect(served_by(:ro, 4).tally).to eq('ro1' => 2, 'ro2' => 2)
    end

    it 'round-robins each mode on its own' do
      ro = Array.new(4) { served_by(:rw, 1) && served_by(:ro, 1).first }

      expect(ro.tally).to eq('ro1' => 2, 'ro2' => 2)
    end

    it 'uses every instance for :any, the default' do
      expect(Array.new(3) { pool.eval('return 1').first }).to contain_exactly('rw', 'ro1', 'ro2')
    end

    it 'prefers read-only instances for :prefer_ro' do
      expect(served_by(:prefer_ro, 4)).to all(start_with('ro'))
    end

    it 'prefers the writable instance for :prefer_rw' do
      expect(served_by(:prefer_rw, 2)).to eq(%w[rw rw])
    end

    it 'follows a role change reported through box.status' do
      pool
      change_role(servers['ro1'], roles, 'ro1', false)
      wait_for { served_by(:rw, 2).include?('ro1') }
      change_role(servers['rw'], roles, 'rw', true)

      wait_for { served_by(:rw, 2) == %w[ro1 ro1] }
      expect(served_by(:ro, 2)).to contain_exactly('rw', 'ro2')
    end

    it 'runs transactions on the writable instance' do
      expect(pool.transaction { |tx| tx.eval('return 1') }).to eq(['rw'])
    end

    it 'rejects an unknown mode' do
      expect { pool.ping(mode: :primary) }.to raise_error(ArgumentError, /unknown mode :primary/)
    end

    it 'shows only the addresses when inspected' do
      expect(pool.inspect).to eq("#<Tarantool::Client::Pool #{servers.values.map(&:path).join(', ')}>")
    end

    context 'without read-only instances' do
      let(:roles) { { 'rw' => false } }

      it 'falls back to the writable instance for :prefer_ro' do
        expect(served_by(:prefer_ro, 2)).to eq(%w[rw rw])
      end

      it 'raises NoAvailableInstanceError for :ro' do
        expect { pool.ping(mode: :ro) }.to raise_error(Tarantool::NoAvailableInstanceError, /mode :ro/)
      end
    end

    context 'without a writable instance' do
      let(:roles) { { 'ro1' => true } }

      it 'falls back to a read-only instance for :prefer_rw' do
        expect(served_by(:prefer_rw, 2)).to eq(%w[ro1 ro1])
      end

      it 'raises NoAvailableInstanceError for a transaction' do
        expect { pool.transaction { nil } }.to raise_error(Tarantool::NoAvailableInstanceError, /mode :rw/)
      end
    end

    context 'when an instance is down at start' do
      before { servers['ro2'].refusing = true }

      it 'starts with the others and adds it once it answers' do
        expect(served_by(:ro, 2)).to eq(%w[ro1 ro1])
        servers['ro2'].refusing = false

        wait_for { served_by(:ro, 2).include?('ro2') }
        expect(served_by(:ro, 2)).to contain_exactly('ro1', 'ro2')
      end
    end
  end
end
