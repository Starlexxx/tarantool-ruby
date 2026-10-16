# frozen_string_literal: true

RSpec.describe Tarantool::Model, :integration do
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
  let(:client) do
    Tarantool::Client.new(ENV.fetch('TARANTOOL_MODEL_URI', 'tcp://app:secret@localhost:3321'), instrumenter:)
  end

  before do
    stub_const('User', Class.new do
      include Tarantool::Model

      attribute :id, :integer
      attribute :email, :string
      attribute :age, :integer, default: 0
    end)
    User.storage = Tarantool::Model::Storage::Box.new(client)
  end

  after { client.close }

  it 'reports model reads through the client instrumenter without the key' do
    expect { User.find(987_654) }.to raise_error(Tarantool::Model::RecordNotFound)

    select = events.map(&:last).find { |payload| payload[:request] == :select }
    expect(select.keys).to contain_exactly(:space, :index, :request, :address)
    expect(select[:space].to_s).to eq('users')
  end
end
