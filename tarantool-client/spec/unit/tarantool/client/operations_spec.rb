# frozen_string_literal: true

RSpec.describe Tarantool::Client::Operations do
  subject(:target) { target_class.new(data) }

  let(:data) { [[1, 'a@b.c']] }
  let(:requests) { Tarantool::Client::Protocol::Requests }
  let(:target_class) do
    Class.new do
      include Tarantool::Client::Operations

      attr_reader :performed

      def initialize(data)
        @data = data
        @performed = []
      end

      private

      def perform(request, timeout: nil)
        @performed << [request, timeout]
        Tarantool::Client::Protocol::Response.new({ 0x00 => 0, 0x01 => 1 }, { 0x30 => @data })
      end

      def resolve(space, index)
        [space == :users ? 512 : space, index == :email ? 1 : index]
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

  it 'passes the per-request timeout' do
    target.select(:users, 1, timeout: 0.5)

    expect(target.performed.last.last).to eq(0.5)
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

  it 'returns nil for upsert' do
    expect(target.upsert(:users, [1, 'a@b.c'], [['+', 2, 1]])).to be_nil
    expect(last_request).to eq(requests::Upsert.new(space_id: 512, tuple: [1, 'a@b.c'], operations: [['+', 2, 1]]))
  end

  it 'returns all values from call and eval' do
    expect(target.call('api.get', [1])).to eq(data)
    expect(target.eval('return ...', [1])).to eq(data)
    expect(last_request).to eq(requests::Eval.new(expression: 'return ...', arguments: [1]))
  end
end
