# frozen_string_literal: true

RSpec.describe Tarantool::Client::Transport::Connection do
  let(:handler) { nil }
  let(:server) { FakeTarantool.new(&handler) }
  let(:config) { Tarantool::Client::Configuration.build(server.uri, user: 'app', password: 'secret') }
  let(:connection) { described_class.new(config).connect }

  def eval_request(expression)
    Tarantool::Client::Protocol::Requests::Eval.new(expression:, arguments: [])
  end

  after { server.stop }

  describe '#connect' do
    after { connection.close }

    it 'reads the server version from the greeting' do
      expect(connection.greeting.version).to eq('2.11.1')
    end

    it 'stores features announced by the server' do
      expect(connection.server_features).to eq([0, 1, 2, 3])
    end
  end

  describe 'connect failures' do
    it 'raises AuthenticationError when credentials are rejected' do
      rejecting = FakeTarantool.new(auth_error: 'User not found or supplied credentials are invalid')
      config = Tarantool::Client::Configuration.build(rejecting.uri, user: 'app', password: 'wrong')

      expect { described_class.new(config).connect }.to raise_error(Tarantool::AuthenticationError, /credentials/)
    ensure
      rejecting.stop
    end

    it 'raises ConnectionError when nothing listens' do
      config = Tarantool::Client::Configuration.build('unix:/nonexistent/tarantool.sock')

      expect { described_class.new(config).connect }.to raise_error(Tarantool::ConnectionError, /nonexistent/)
    end
  end

  describe '#perform' do
    after { connection.close }

    context 'when the server answers' do
      let(:handler) { ->(request, fake) { fake.reply(request, [request.body[0x27]]) } }

      it 'returns the response' do
        expect(connection.perform(eval_request('return 1'), timeout: 1).data).to eq(['return 1'])
      end
    end

    context 'when the server returns an error' do
      let(:handler) { ->(request, fake) { fake.reply_error(request, code: 3, message: 'Duplicate key') } }

      it 'raises ServerError with the error code' do
        expect { connection.perform(eval_request('x'), timeout: 1) }
          .to raise_error(Tarantool::ServerError, 'Duplicate key') { |error| expect(error.code).to eq(3) }
      end
    end

    context 'when the server drops the connection' do
      let(:handler) { ->(_request, fake) { fake.disconnect } }

      it 'raises ConnectionError' do
        expect { connection.perform(eval_request('x'), timeout: 1) }.to raise_error(Tarantool::ConnectionError, /lost/)
      end
    end

    it 'matches out-of-order responses by sync' do
      threads = %w[first second].map { |expr| Thread.new { connection.perform(eval_request(expr), timeout: 1).data } }
      requests = Array.new(2) { server.next_request }
      requests.reverse_each { |request| server.reply(request, [request.body[0x27]]) }

      expect(threads.map(&:value)).to eq([['first'], ['second']])
    end

    it 'raises TimeoutError when the server stays silent' do
      expect { connection.perform(eval_request('x'), timeout: 0.05) }.to raise_error(Tarantool::TimeoutError)
    end

    it 'raises ClientClosedError after close' do
      connection.close

      expect { connection.perform(eval_request('x'), timeout: 1) }.to raise_error(Tarantool::ClientClosedError)
    end
  end
end
