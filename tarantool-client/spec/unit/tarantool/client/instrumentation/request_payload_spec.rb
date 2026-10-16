# frozen_string_literal: true

RSpec.describe Tarantool::Client::Instrumentation::RequestPayload do
  let(:requests) { Tarantool::Client::Protocol::Requests }

  it 'names a request without fields' do
    expect(described_class.build(requests::Ping.new)).to eq(request: :ping)
    expect(described_class.build(requests::Commit.new)).to eq(request: :commit)
    expect(described_class.build(requests::Begin.new(isolation: :default, timeout: nil))).to eq(request: :begin)
  end

  it 'names the function of a call and leaves its arguments out' do
    expect(described_class.build(requests::Call.new(function_name: 'f', arguments: ['secret'])))
      .to eq(request: :call, function: 'f')
  end

  it 'leaves the expression and arguments of an eval out' do
    expect(described_class.build(requests::Eval.new(expression: 'return ...', arguments: ['secret'])))
      .to eq(request: :eval)
  end

  it 'reports SQL text without bindings and a prepared statement by id' do
    expect(described_class.build(requests::Execute.new(statement: 'SELECT ?', bindings: ['secret'])))
      .to eq(request: :execute, sql: 'SELECT ?')
    expect(described_class.build(requests::Execute.new(statement: 7, bindings: [])))
      .to eq(request: :execute, statement_id: 7)
    expect(described_class.build(requests::Prepare.new(statement: 7))).to eq(request: :prepare, statement_id: 7)
  end

  it 'keeps space and index of a select' do
    select = requests::Select.new(space_id: 512, index_id: 1, key: ['secret'], limit: 1, offset: 0, iterator: :eq)

    expect(described_class.describe({ space: :users, index: :email }, select))
      .to eq(space: :users, index: :email, request: :select)
  end

  it 'drops the index of a request that has none' do
    insert = requests::Insert.new(space_id: 512, tuple: [1, 'secret'])

    expect(described_class.describe({ space: :users, index: 0 }, insert)).to eq(space: :users, request: :insert)
  end
end
