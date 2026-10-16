# frozen_string_literal: true

RSpec.describe Tarantool::Client::Pool do
  before { skip 'fork not supported on this platform' unless Process.respond_to?(:fork) }

  let(:rw_server) { ForkFakeTarantool.new(read_only: false) }
  let(:ro_server) { ForkFakeTarantool.new(read_only: true) }

  describe 'fork safety' do
    context 'with rw and ro members' do
      let(:pool) do
        described_class.new([rw_server.uri, ro_server.uri],
                            request_timeout: 2, connect_timeout: 2, reconnect_delay: 0.05)
      end

      after do
        pool.close
        rw_server.stop
        ro_server.stop
      end

      it 'routes mode: :rw and mode: :ro correctly after fork, parent unaffected' do
        expect(pool.ping(mode: :rw)).to be(true)
        child_pid = fork do
          rw_server.restart_after_fork
          ro_server.restart_after_fork
          pool.ping(mode: :rw) && pool.ping(mode: :ro) ? exit(0) : exit(1)
        end
        _, status = Process.wait2(child_pid)
        expect(status.exitstatus).to eq(0)
        expect(pool.ping(mode: :rw)).to be(true)
      end
    end

    context 'with an instrumenter' do
      let(:instrumenter) { RecordingInstrumenter.new }
      let(:pool) do
        described_class.new([rw_server.uri, ro_server.uri], request_timeout: 2, connect_timeout: 2,
                                                            reconnect_delay: 0.05, instrumenter:)
      end

      after do
        pool.close
        rw_server.stop
        ro_server.stop
      end

      it 'reports a fork for every member in the child' do
        pool.ping
        child_pid = fork do
          rw_server.restart_after_fork
          ro_server.restart_after_fork
          pool.ping
          addresses = instrumenter.payloads('fork.tarantool').map { |payload| payload[:address] }
          exit(addresses.sort == [rw_server.path, ro_server.path].sort ? 0 : 1)
        end
        _, status = Process.wait2(child_pid)

        expect(status.exitstatus).to eq(0)
      end
    end

    context 'with a member down at fork time' do
      let(:down_server) { ForkFakeTarantool.new(read_only: true).tap { |s| s.refusing = true } }
      let(:pool) do
        described_class.new([rw_server.uri, down_server.uri],
                            request_timeout: 2, connect_timeout: 2, reconnect_delay: 0.05)
      end

      after do
        pool.close
        rw_server.stop
        down_server.stop
      end

      def wait_for_ro(pool, timeout: 5)
        deadline = Time.now + timeout
        loop do
          pool.ping(mode: :ro) and return true
        rescue Tarantool::NoAvailableInstanceError
          return false if Time.now > deadline

          sleep 0.05
        end
      end

      it 'mode: :rw succeeds in child when down member stays down' do
        expect(pool.ping(mode: :rw)).to be(true)
        child_pid = fork do
          rw_server.restart_after_fork
          exit(pool.ping(mode: :rw) ? 0 : 1)
        rescue StandardError
          exit 1
        end
        _, status = Process.wait2(child_pid)
        expect(status.exitstatus).to eq(0)
      end

      it 'down member joins rotation in child once its server accepts' do
        expect(pool.ping(mode: :rw)).to be(true)
        child_pid = fork do
          rw_server.restart_after_fork
          down_server.refusing = false
          down_server.restart_after_fork
          exit(wait_for_ro(pool) ? 0 : 1)
        end
        _, status = Process.wait2(child_pid)
        expect(status.exitstatus).to eq(0)
      end
    end
  end
end
