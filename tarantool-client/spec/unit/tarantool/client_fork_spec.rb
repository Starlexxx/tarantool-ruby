# frozen_string_literal: true

RSpec.describe Tarantool::Client do
  before { skip 'fork not supported on this platform' unless Process.respond_to?(:fork) }

  let(:server) { ForkFakeTarantool.new }
  let!(:client) { described_class.new(server.uri, request_timeout: 2, connect_timeout: 2) }

  after do
    client.close
    server.stop
  end

  describe 'fork safety' do
    it 'reconnects in child on first use and leaves parent unaffected' do
      expect(client.ping).to be(true)
      child_pid = fork do
        server.restart_after_fork
        exit(client.ping ? 0 : 1)
      end
      _, status = Process.wait2(child_pid)
      expect(status.exitstatus).to eq(0)
      expect(client.ping).to be(true)
    end

    it 'closes without hanging in child and leaves parent unaffected' do
      expect(client.ping).to be(true)
      child_pid = fork do
        client.close
        exit 0
      end
      _, status = Process.wait2(child_pid)
      expect(status.exitstatus).to eq(0)
      expect(client.ping).to be(true)
    end

    it 'connected? is false in child before first op and true after' do
      expect(client.connected?).to be(true)
      child_pid = fork do
        before_op = client.connected?
        server.restart_after_fork
        client.ping
        exit(!before_op && client.connected? ? 0 : 1)
      end
      _, status = Process.wait2(child_pid)
      expect(status.exitstatus).to eq(0)
    end

    it 'does not reinitialize when called from the same process' do
      link_before = client.instance_variable_get(:@link)
      client.ping
      expect(client.instance_variable_get(:@link)).to equal(link_before)
    end

    context 'with a pre-fork watcher' do
      let(:received) { Thread::Queue.new }

      it 'fires in child after resubscribe' do
        client.watch('box.status') { |_key, val| received << val }
        received.pop(timeout: 2)
        child_pid = fork do
          server.restart_after_fork
          client.ping
          val = received.pop(timeout: 3)
          exit(val.is_a?(Hash) ? 0 : 1)
        end
        _, status = Process.wait2(child_pid)
        expect(status.exitstatus).to eq(0)
      end
    end

    context 'with a named-space operation in child' do
      let(:server) do
        ForkFakeTarantool.new do |request|
          case request.body[0x10]
          when 281 then [[512, 1, 'test', 'memtx', 0, {}, []]]
          when 289 then [[512, 0, 'primary', 'tree', { 'unique' => true }, []]]
          else []
          end
        end
      end

      it 'resolves name and returns rows in child' do
        expect(client.ping).to be(true)
        child_pid = fork do
          server.restart_after_fork
          rows = client.select('test', [])
          exit(rows == [] ? 0 : 1)
        rescue StandardError
          exit 1
        end
        _, status = Process.wait2(child_pid)
        expect(status.exitstatus).to eq(0)
      end
    end

    context 'with an instrumenter' do
      let(:instrumenter) { RecordingInstrumenter.new }
      let(:client) { described_class.new(server.uri, request_timeout: 2, connect_timeout: 2, instrumenter:) }

      def client_with_password(log)
        described_class.new(server.uri, password: 'secret', instrumenter:, logger: Logger.new(log))
      end

      def fork_succeeded?(log)
        instrumenter.payloads('fork.tarantool').any? &&
          !instrumenter.events.inspect.include?('secret') && !log.string.include?('secret')
      end

      it 'reports the reopened connection in the child' do
        client.ping
        child_pid = fork do
          server.restart_after_fork
          client.ping
          exit(instrumenter.payloads('fork.tarantool') == [{ address: server.path }] ? 0 : 1)
        end
        _, status = Process.wait2(child_pid)

        expect(status.exitstatus).to eq(0)
      end

      it 'keeps the password out of the fork event and its log line' do
        secret_client = client_with_password(log = StringIO.new)
        child_pid = fork do
          server.restart_after_fork
          secret_client.ping
          exit(fork_succeeded?(log) ? 0 : 1)
        end
        _, status = Process.wait2(child_pid)

        expect(status.exitstatus).to eq(0)
      ensure
        secret_client&.close
      end
    end

    context 'with a stream created before fork' do
      let(:pre_fork_stream) do
        link = client.instance_variable_get(:@link)
        cache = client.instance_variable_get(:@schema_cache)
        s = Tarantool::Client::Stream.new(connection: link.connection, schema_cache: cache,
                                          id: 99, request_timeout: 2)
        s.instance_variable_set(:@state, :active)
        s
      end

      it 'raises ConnectionError mentioning fork when stream used in child' do
        stream = pre_fork_stream
        child_pid = fork do
          stream.ping
          exit 1
        rescue Tarantool::ConnectionError => e
          exit(e.message.include?('fork') ? 0 : 1)
        end
        _, status = Process.wait2(child_pid)
        expect(status.exitstatus).to eq(0)
      end
    end
  end
end
