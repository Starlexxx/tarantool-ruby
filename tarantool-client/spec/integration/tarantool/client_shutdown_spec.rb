# frozen_string_literal: true

# Stops the instances with SIGTERM, so it runs only against the dedicated failover pair.
RSpec.describe Tarantool::Client, :failover do
  def container(command, name)
    system(ENV.fetch('CONTAINER_CLI', 'docker'), command, *(['-t', '10'] if command == 'stop'), name,
           out: File::NULL, exception: true)
  end

  def wait_until_serving(uri)
    wait_for(timeout: 30) do
      Tarantool::Client.new(uri, reconnect: false).close
      true
    rescue Tarantool::Error
      false
    end
  end

  FailoverHelpers.uris.zip(FailoverHelpers.containers).each do |uri, name|
    context "when #{name} is stopped" do
      subject(:client) { described_class.new(uri, reconnect_delay: 0.1, instrumenter:) }

      let(:instrumenter) { RecordingInstrumenter.new }

      after do
        client.close
        container('start', name)
        wait_until_serving(uri)
      end

      it 'finishes the request in flight, reports the shutdown and reconnects when the instance is back' do
        in_flight = Thread.new { client.eval('require("fiber").sleep(1) return 1') }
        sleep 0.2
        container('stop', name)

        expect(in_flight.value).to eq([1])
        expect(instrumenter.payloads('shutdown.tarantool').first).to include(pending: 1)
        expect(instrumenter.payloads('disconnect.tarantool').first[:reason]).to include('is shutting down')
      end
    end
  end

  context 'with a pool over both instances' do
    subject(:pool) { described_class::Pool.new(uris, reconnect_delay: 0.1) }

    let(:uris) { FailoverHelpers.uris }
    let(:stopped) { FailoverHelpers.containers.first }

    after do
      pool.close
      container('start', stopped)
      wait_until_serving(uris.first)
    end

    def answers_during(seconds)
      deadline = Tarantool::Client::Transport::Deadline.after(seconds)
      [].tap do |answers|
        until Tarantool::Client::Transport::Deadline.remaining(deadline).zero?
          answers << pool.select(:users, [], limit: 1, mode: :any)
          sleep 0.02
        end
      end
    end

    it 'keeps answering through the other instance while one is stopped, without an error' do
      pool.ping(mode: :any)
      stopper = Thread.new do
        sleep 0.2
        container('stop', stopped)
      end
      answers = answers_during(1.5)
      stopper.join

      expect(answers.size).to be > 10
    end
  end
end
