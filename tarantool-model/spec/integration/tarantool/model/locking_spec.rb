# frozen_string_literal: true

RSpec.describe Tarantool::Model::Locking, :integration do
  let(:uri) { ENV.fetch('TARANTOOL_MODEL_URI', 'tcp://app:secret@localhost:3321') }
  let(:clients) { Array.new(2) { Tarantool::Client.new(uri) } }
  let(:models) do
    clients.map do |client|
      model = Class.new do
        include Tarantool::Model

        self.space_name = :users
        self.locking_column = :age

        attribute :id, :integer
        attribute :email, :string
        attribute :age, :integer, default: 0
      end
      model.storage = Tarantool::Model::Storage::Box.new(client)

      model
    end
  end

  before do
    stub_const('LockedUser', models.first)
    stub_const('OtherLockedUser', models.last)
    LockedUser.create!(id: 9001, email: 'lock@x')
  end

  after do
    clients.first.delete(:users, [9001])
    clients.each(&:close)
  end

  def save_concurrently(first, second)
    [first, second].map.with_index do |user, index|
      Thread.new do
        user.update!(email: "winner#{index}@x")
        :saved
      rescue Tarantool::Model::StaleObjectError => e
        e
      end
    end.map(&:value)
  end

  it 'lets exactly one of two concurrent saves through' do
    first = LockedUser.find(9001)
    second = OtherLockedUser.find(9001)

    results = save_concurrently(first, second)
    winner = results.index(:saved)

    expect(results.count(:saved)).to eq(1)
    expect(results.grep(Tarantool::Model::StaleObjectError).size).to eq(1)
    expect(clients.first.select(:users, [9001], as: :hash).first).to include(email: "winner#{winner}@x", age: 1)
  end

  it 'raises StaleObjectError for a save after another record of the row was saved' do
    first = LockedUser.find(9001)
    second = LockedUser.find(9001)
    first.update!(email: 'first@x')

    expect { second.update!(email: 'second@x') }.to raise_error(Tarantool::Model::StaleObjectError)
    expect(clients.first.select(:users, [9001], as: :hash).first).to include(email: 'first@x', age: 1)
  end
end
