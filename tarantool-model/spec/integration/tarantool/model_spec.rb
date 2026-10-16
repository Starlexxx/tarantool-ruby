# frozen_string_literal: true

RSpec.describe Tarantool::Model, :integration do
  let(:client) { Tarantool::Client.new(ENV.fetch('TARANTOOL_MODEL_URI', 'tcp://app:secret@localhost:3321')) }
  let(:account) do
    Class.new do
      include Tarantool::Model

      attribute :id, :integer
      attribute :email, :string
      attribute :balance, :decimal
      attribute :token, Tarantool::Model::Types::UUID.new
      attribute :created_at, :datetime
      attribute :period, Tarantool::Model::Types::Interval.new
      attribute :avatar, Tarantool::Model::Types::Binary.new
      attribute :tags
    end
  end

  before do
    client.eval('box.space.accounts:truncate()')
    stub_const('Account', account)
    Account.storage = Tarantool::Model::Storage::Box.new(client)
  end

  after { client.close }

  it 'gets the id from the sequence for a nil primary key' do
    first = Account.create!(email: 'a')

    expect(Account.create!(email: 'b').id).to eq(first.id + 1)
  end

  it 'round-trips every mapped type' do
    values = {
      balance: BigDecimal('12.345'), token: '6f1c3c2e-8f0a-4b8e-9a51-2a8f0f6a7c11',
      created_at: Time.at(1_700_000_000, 123_456_789, :nsec, in: '+03:00'),
      period: Tarantool::Client::Interval.new(day: 2, hour: 3), avatar: "\xFF\x00".b, tags: { 'a' => [1, 2] }
    }
    id = Account.create!(email: 'a', **values).id

    expect(Account.find(id)).to have_attributes(**values, token: Tarantool::Client::UUID.new(value: values[:token]))
  end

  it 'raises SchemaMismatchError for an attribute missing from the format' do
    Account.attribute :phone, :string

    expect { Account.find(1) }.to raise_error(Tarantool::Model::SchemaMismatchError, /phone/)
  end

  it 'raises RecordNotUnique for a duplicate unique secondary key' do
    Account.create!(email: 'a')

    expect { Account.create!(email: 'a') }.to raise_error(Tarantool::Model::RecordNotUnique)
  end

  it 'pages with after and walks with find_each' do
    3.times { |i| Account.create!(email: "u#{i}") }
    first = Account.all.limit(2).to_a

    expect(Account.all.after(first.last).map(&:email)).to eq(['u2'])
    expect(Account.find_each(batch_size: 2).count).to eq(3)
  end
end
