# frozen_string_literal: true

RSpec.describe Tarantool::Client::Operations do
  subject(:target) { target_class.new(body) }

  let(:data) { [[1, 'a@b.c']] }
  let(:body) { { 0x30 => data } }
  let(:requests) { Tarantool::Client::Protocol::Requests }
  let(:target_class) do
    Class.new do
      include Tarantool::Client::Operations

      attr_reader :performed, :on_push, :format

      def initialize(body)
        @body = body
        @performed = []
      end

      private

      def perform(request, timeout: nil, on_push: nil)
        @performed << [request, timeout]
        @on_push = on_push

        Tarantool::Client::Protocol::Response.new({ 0x00 => 0, 0x01 => 1 }, @body)
      end

      def perform_on_space(space, index, timeout:, format: false)
        @format = format

        perform(yield(space == :users ? 512 : space, index == :email ? 1 : index, users_info), timeout:)
      end

      def users_info
        field = Tarantool::Client::SpaceInfo::Field
        fields = %w[id email].map { |name| field.new(name:, type: 'any', is_nullable: false) }

        Tarantool::Client::SpaceInfo.new(id: 512, name: 'users', fields:, indexes: {})
      end

      def lookup_space(space, timeout)
        @performed << [:lookup_space, space, timeout]

        :info
      end
    end
  end

  def last_request = target.performed.last.first

  it 'pings' do
    expect(target.ping).to be(true)
    expect(last_request).to eq(requests::Ping.new)
  end

  it 'selects with resolved ids and defaults' do
    expect(target.select(:users, 'a@b.c', index: :email)).to eq(data)
    expect(last_request).to eq(
      requests::Select.new(space_id: 512, index_id: 1, key: ['a@b.c'], limit: 0xffff_ffff, offset: 0, iterator: :eq)
    )
  end

  it 'selects after a tuple' do
    target.select(:users, [], iterator: :all, limit: 2, after: [1, 'a@b.c'])

    expect(last_request.after).to eq([1, 'a@b.c'])
  end

  it 'passes the per-request timeout' do
    target.select(:users, 1, timeout: 0.5)

    expect(target.performed.last.last).to eq(0.5)
  end

  it 'looks up space info with the per-request timeout' do
    expect(target.space_info(:users, timeout: 0.5)).to eq(:info)
    expect(target.performed.last).to eq([:lookup_space, :users, 0.5])
  end

  it 'returns the affected tuple for insert, replace, update and delete' do
    expect(target.insert(:users, [1, 'a@b.c'])).to eq([1, 'a@b.c'])
    expect(target.replace(:users, [1, 'a@b.c'])).to eq([1, 'a@b.c'])
    expect(target.update(:users, 1, [['=', 1, 'x']])).to eq([1, 'a@b.c'])
  end

  it 'builds update and delete against the chosen index' do
    target.update(:users, 'a@b.c', [['=', 1, 'x']], index: :email)
    expect(last_request).to eq(
      requests::Update.new(space_id: 512, index_id: 1, key: ['a@b.c'], operations: [['=', 1, 'x']])
    )

    target.delete(:users, 'a@b.c', index: :email)
    expect(last_request).to eq(requests::Delete.new(space_id: 512, index_id: 1, key: ['a@b.c']))
  end

  it 'deletes by any index through BatchDelete' do
    batch_delete = instance_double(Tarantool::Client::BatchDelete, call: 3)
    allow(Tarantool::Client::BatchDelete).to receive(:new).and_return(batch_delete)

    expect(target.delete_by(:users, 18, index: :age)).to eq(3)
    expect(Tarantool::Client::BatchDelete).to have_received(:new)
      .with(target, :users, 18, index: :age, iterator: :eq, batch_size: 1000, timeout: nil)
  end

  it 'offers delete_by on Client, Stream and Pool' do
    [Tarantool::Client, Tarantool::Client::Stream, Tarantool::Client::Pool].each do |klass|
      expect(klass.public_method_defined?(:delete_by)).to be(true)
    end
  end

  it 'returns nil for upsert' do
    expect(target.upsert(:users, [1, 'a@b.c'], [['+', 2, 1]])).to be_nil
    expect(last_request).to eq(requests::Upsert.new(space_id: 512, tuple: [1, 'a@b.c'], operations: [['+', 2, 1]]))
  end

  it 'returns all values from call and eval' do
    expect(target.call('api.get', [1])).to eq(data)
    expect(target.eval('return ...', [1])).to eq(data)
    expect(last_request).to eq(requests::Eval.new(expression: 'return ...', arguments: [1]))
  end

  it 'passes on_push through call' do
    on_push = ->(_message) {}
    target.call('api.get', [1], on_push:)

    expect(target.on_push).to be(on_push)
  end

  it 'wraps a Hash key in an array instead of converting it to pairs' do
    target.select(:users, { email: 'a@b.c' })

    expect(last_request.key).to eq([{ email: 'a@b.c' }])
  end

  it 'wraps a Time key in an array instead of coercing it' do
    time = Time.now
    target.select(:users, time)

    expect(last_request.key).to eq([time])
  end

  describe 'as:' do
    it 'returns tuples without needing the format by default' do
      expect(target.select(:users, 1)).to eq(data)
      expect(target.format).to be(false)
    end

    it 'returns Hashes by the format for as: :hash' do
      expect(target.select(:users, 1, as: :hash)).to eq([{ id: 1, email: 'a@b.c' }])
      expect(target.format).to be(true)
    end

    it 'returns rows with the raw tuple for as: :row' do
      row = Tarantool::Client::Row.new(tuple: [1, 'a@b.c'], attributes: { id: 1, email: 'a@b.c' })

      expect(target.select(:users, 1, as: :row)).to eq([row])
    end

    it 'shapes the tuple of insert, replace, update and delete' do
      expect(target.insert(:users, [1, 'a@b.c'], as: :hash)).to eq(id: 1, email: 'a@b.c')
      expect(target.replace(:users, [1, 'a@b.c'], as: :hash)).to eq(id: 1, email: 'a@b.c')
      expect([target.update(:users, 1, [], as: :hash), target.delete(:users, 1, as: :hash)])
        .to eq([{ id: 1, email: 'a@b.c' }] * 2)
    end

    it 'rejects an unknown shape before sending' do
      expect { target.select(:users, 1, as: :json) }.to raise_error(ArgumentError, /as: :json/)
      expect(target.performed).to be_empty
    end
  end

  describe 'Hash tuples' do
    it 'builds the tuple of insert and replace by the format' do
      target.insert(:users, { email: 'a@b.c', id: 1 })
      expect(last_request.tuple).to eq([1, 'a@b.c'])
      expect(target.format).to be(true)

      target.replace(:users, { 'id' => 2 })
      expect(last_request.tuple).to eq([2, nil])
    end

    it 'builds the tuple of upsert by the format' do
      target.upsert(:users, { id: 1 }, [['+', 'email', 1]])

      expect(last_request).to eq(requests::Upsert.new(space_id: 512, tuple: [1, nil], operations: [['+', 'email', 1]]))
    end

    it 'does not need the format for an Array upsert' do
      target.upsert(:users, [1], [])

      expect(target.format).to be(false)
    end
  end

  context 'with SQL' do
    let(:body) { { 0x32 => [{ 0x00 => 'id' }], 0x30 => [[1]], 0x43 => 7 } }

    it 'executes SQL text with bindings' do
      expect(target.execute('SELECT id FROM t WHERE id = ?', [1])).to have_attributes(rows: [[1]], columns: ['id'])
      expect(last_request).to eq(requests::Execute.new(statement: 'SELECT id FROM t WHERE id = ?', bindings: [1]))
    end

    it 'executes a prepared statement by its id' do
      statement = Tarantool::Client::PreparedStatement.new(7, ->(*) {})
      target.execute(statement, [1])
      expect(last_request).to eq(requests::Execute.new(statement: 7, bindings: [1]))
    end

    it 'prepares a statement that executes through the same target' do
      statement = target.prepare('SELECT id FROM t WHERE id = ?', timeout: 0.5)

      expect(target.performed.last).to eq([requests::Prepare.new(statement: 'SELECT id FROM t WHERE id = ?'), 0.5])
      expect(statement.execute([1]).rows).to eq([[1]])
      expect(last_request).to eq(requests::Execute.new(statement: 7, bindings: [1]))
    end
  end
end
