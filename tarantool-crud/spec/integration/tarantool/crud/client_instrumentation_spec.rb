# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Client, :integration do
  subject(:crud) { described_class.new(connection) }

  let(:uri) { ENV.fetch('TARANTOOL_CRUD_URI', 'tcp://app:secret@localhost:3311') }
  let(:events) { [] }
  let(:instrumenter) do
    recorded = events
    Class.new do
      define_method(:instrument) do |name, payload, &block|
        block.call
      ensure
        recorded << [name, payload]
      end
    end.new
  end
  let(:connection) { Tarantool::Client.new(uri, instrumenter:) }

  after { connection.close }

  it 'reports crud calls through the client instrumenter without their arguments' do
    crud.space(:customers).get(987_654)

    payload = events.map(&:last).find { |candidate| candidate[:function] == 'crud.get' }
    expect(payload).to eq(request: :call, function: 'crud.get', address: connection.config.address)
  end
end
