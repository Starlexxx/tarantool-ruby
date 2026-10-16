# frozen_string_literal: true

require 'delegate'

RSpec.describe Tarantool::Client, :integration do
  subject(:client) { described_class.new(uri) }

  let(:uri) { ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301') }
  let(:space) { :delete_by_users }

  let(:inserting) do
    Class.new(SimpleDelegator) do
      def select(...)
        @selects = (@selects || 0) + 1
        insert_around_cursor if @selects == 2

        __getobj__.select(...)
      end

      private

      def insert_around_cursor
        __getobj__.insert(:delete_by_users, [15, 18])
        __getobj__.insert(:delete_by_users, [25, 18])
      end
    end.new(client)
  end

  before do
    drop_space
    client.eval(<<~LUA)
      local s = box.schema.space.create('delete_by_users', {
          format = {{name = 'id', type = 'unsigned'}, {name = 'age', type = 'unsigned'}},
      })
      s:create_index('primary', {parts = {'id'}})
      s:create_index('age', {parts = {'age'}, unique = false})
    LUA
    [[10, 18], [20, 18], [30, 18], [40, 19]].each { |tuple| client.insert(space, tuple) }
  end

  after do
    drop_space
    client.close
  end

  def drop_space
    client.eval('if box.space.delete_by_users then box.space.delete_by_users:drop() end')
  end

  it 'deletes every tuple matching a non-unique index across batches' do
    expect(client.delete_by(space, [18], index: :age, batch_size: 2)).to eq(3)
    expect(client.select(space)).to eq([[40, 19]])
  end

  it 'continues select after a tuple that was already deleted' do
    page = client.select(space, [18], index: :age, limit: 2)
    client.delete(space, [page.last.first])

    expect(client.select(space, [18], index: :age, limit: 2, after: page.last)).to eq([[30, 18]])
  end

  it 'deletes tuples inserted ahead of the cursor and keeps those inserted behind it' do
    count = Tarantool::Client::BatchDelete.new(
      inserting, space, [18], index: :age, iterator: :eq, batch_size: 2, timeout: nil
    ).call

    expect(count).to eq(4)
    expect(client.select(space)).to eq([[15, 18], [40, 19]])
  end

  it 'deletes atomically inside a transaction' do
    expect do
      client.transaction do |tx|
        tx.delete_by(space, [18], index: :age, batch_size: 2)
        raise 'boom'
      end
    end.to raise_error(RuntimeError, 'boom')
    expect(client.select(space).size).to eq(4)
  end

  it 'commits deletes made inside a transaction' do
    count = client.transaction { |tx| tx.delete_by(space, [18], index: :age, batch_size: 2) }

    expect(count).to eq(3)
    expect(client.select(space)).to eq([[40, 19]])
  end
end
