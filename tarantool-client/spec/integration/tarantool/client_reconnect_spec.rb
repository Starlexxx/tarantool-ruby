# frozen_string_literal: true

# Restarts the instances, so it runs only against the dedicated failover pair.
RSpec.describe Tarantool::Client, :failover do
  uris = ENV.fetch('TARANTOOL_FAILOVER_URIS', '').split(',')
  containers = ENV.fetch('TARANTOOL_FAILOVER_CONTAINERS', '').split(',')

  uris.zip(containers).each do |uri, container|
    context "when #{container} restarts" do
      subject(:client) { described_class.new(uri, reconnect_delay: 0.1) }

      let(:events) { Thread::Queue.new }

      after { client.close }

      define_method(:restart) do
        client
        system(ENV.fetch('CONTAINER_CLI', 'docker'), 'restart', '-t', '0', container, out: File::NULL, exception: true)
        wait_for(timeout: 30) do
          client.ping
        rescue Tarantool::Error
          false
        end
      end

      it 'serves requests again once the instance is back' do
        restart

        expect(client.select(:users, [], limit: 1)).to be_an(Array)
      end

      it 'delivers box.status again after re-subscribing' do
        client.watch('box.status') { |_key, value| events << value }
        events.pop(timeout: 1)
        restart

        expect(events.pop(timeout: 30)).to include('is_ro' => false)
      end

      it 'fails a transaction opened before the restart with TransactionError' do
        expect do
          client.transaction do |tx|
            restart
            tx.ping
          end
        end.to raise_error(Tarantool::TransactionError, /connection lost/)
      end
    end
  end
end
