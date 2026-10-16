# frozen_string_literal: true

RSpec.describe Tarantool::Model::Storage::Crud, :crud do
  let(:client) { Tarantool::Client.new(ENV.fetch('TARANTOOL_MODEL_CRUD_URI')) }
  let(:crud) { Tarantool::Crud::Client.new(client) }

  before do
    crud.space(:users).truncate
    stub_const('Customer', Class.new do
      include Tarantool::Model

      self.space_name = :users
      attribute :id, :integer
      attribute :email, :string
      attribute :age, :integer, default: 0
    end)
    Customer.storage = described_class.new(crud)
  end

  after { client.close }

  it 'creates and finds a record; find has no tuple' do
    Customer.create!(id: 1, email: 'a@x', age: 20)
    found = Customer.find(1)

    expect(found).to have_attributes(id: 1, email: 'a@x', age: 20)
    expect(found.tuple).to be_nil
  end

  it 'updates and destroys a record' do
    customer = Customer.create!(id: 1, email: 'a@x')
    customer.update!(email: 'b@x')

    expect(Customer.find(1).email).to eq('b@x')

    customer.destroy

    expect { Customer.find(1) }.to raise_error(Tarantool::Model::RecordNotFound)
  end

  it 'paginates with where and after' do
    (1..5).each { |i| Customer.create!(id: i, email: "u#{i}@x", age: i <= 3 ? 20 : 30) }
    page = Customer.where(index: :age, key: [20], iterator: :ge).limit(2).to_a

    expect(page.map(&:id)).to eq([1, 2])

    next_page = Customer.where(index: :age, key: [20], iterator: :ge).limit(2).after(page.last).to_a

    expect(next_page.first.id).to be > 2
  end

  it 'counts a where condition' do
    (1..4).each { |i| Customer.create!(id: i, email: "u#{i}@x", age: i <= 2 ? 20 : 30) }

    expect(Customer.where(index: :age, key: [20], iterator: :eq).count).to eq(2)
  end

  it 'raises RecordNotUnique for a duplicate id' do
    Customer.create!(id: 1, email: 'a@x')

    expect { Customer.create!(id: 1, email: 'b@x') }.to raise_error(Tarantool::Model::RecordNotUnique)
  end

  it 'raises NotSupportedError for a transaction' do
    expect { Customer.transaction { nil } }.to raise_error(Tarantool::Model::NotSupportedError)
  end

  it 'raises ArgumentError when calling after on a record loaded with find (no tuple)' do
    Customer.create!(id: 1, email: 'a@x')

    expect { Customer.all.after(Customer.find(1)) }.to raise_error(ArgumentError)
  end
end
