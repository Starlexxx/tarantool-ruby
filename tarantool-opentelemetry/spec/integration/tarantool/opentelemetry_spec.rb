# frozen_string_literal: true

RSpec.describe Tarantool::OpenTelemetry, :integration do
  subject(:client) do
    Tarantool::Client.new(ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301'),
                          instrumenter: Tarantool::OpenTelemetry::Instrumenter.new)
  end

  let(:spans) { EXPORTER.finished_spans }

  after { client.close }

  it 'traces a select with the space, the index and the instance' do
    client.select(:users, [], index: :email, limit: 1)

    expect(spans.map(&:name)).to eq(['tarantool.select users'])
    expect(spans.first.attributes).to include('db.operation' => 'select', 'db.tarantool.space' => 'users',
                                              'db.tarantool.index' => 'email', 'server.port' => client.config.port)
  end

  it 'records a failed name resolution on a span without an operation' do
    expect { client.select(:users, [], index: :nope) }.to raise_error(Tarantool::SchemaError)
    expect(spans.first).to have_attributes(name: 'tarantool', status: have_attributes(description: /nope/))
    expect(spans.first.events.map(&:name)).to eq(['exception'])
  end

  it 'traces every step of a transaction' do
    client.transaction { |tx| tx.select(:users, [], limit: 1) }

    expect(spans.map(&:name)).to eq(['tarantool.begin', 'tarantool.select users', 'tarantool.commit'])
  end
end
