# frozen_string_literal: true

RSpec.describe Tarantool::Client::Protocol::Requests do
  def encoded(request)
    [request.type, request.body]
  end

  it 'builds PING' do
    expect(encoded(described_class::Ping.new)).to eq([0x40, {}])
  end

  it 'builds SELECT' do
    request = described_class::Select.new(space_id: 512, index_id: 1, key: ['a'], limit: 10, offset: 2, iterator: :ge)

    expect(encoded(request)).to eq([0x01, { 0x10 => 512, 0x11 => 1, 0x12 => 10, 0x13 => 2, 0x14 => 5, 0x20 => ['a'] }])
  end

  it 'rejects unknown SELECT iterators' do
    expect do
      described_class::Select.new(space_id: 512, index_id: 0, key: [], limit: 1, offset: 0, iterator: :sideways)
    end.to raise_error(ArgumentError, /unknown iterator/)
  end

  it 'builds INSERT and REPLACE' do
    expect(encoded(described_class::Insert.new(space_id: 512, tuple: [1]))).to eq([0x02, { 0x10 => 512, 0x21 => [1] }])
    expect(encoded(described_class::Replace.new(space_id: 512, tuple: [1]))).to eq([0x03, { 0x10 => 512, 0x21 => [1] }])
  end

  it 'builds UPDATE with operations in the tuple key' do
    request = described_class::Update.new(space_id: 512, index_id: 0, key: [1], operations: [['=', 1, 'x']])

    expect(encoded(request)).to eq([0x04, { 0x10 => 512, 0x11 => 0, 0x20 => [1], 0x21 => [['=', 1, 'x']] }])
  end

  it 'builds UPSERT with operations in the ops key' do
    request = described_class::Upsert.new(space_id: 512, tuple: [1, 0], operations: [['+', 1, 1]])

    expect(encoded(request)).to eq([0x09, { 0x10 => 512, 0x21 => [1, 0], 0x28 => [['+', 1, 1]] }])
  end

  it 'builds DELETE' do
    request = described_class::Delete.new(space_id: 512, index_id: 0, key: [1])

    expect(encoded(request)).to eq([0x05, { 0x10 => 512, 0x11 => 0, 0x20 => [1] }])
  end

  it 'builds CALL and EVAL' do
    expect(encoded(described_class::Call.new(function_name: 'f', arguments: [1])))
      .to eq([0x0a, { 0x22 => 'f', 0x21 => [1] }])
    expect(encoded(described_class::Eval.new(expression: 'return 1', arguments: [])))
      .to eq([0x08, { 0x27 => 'return 1', 0x21 => [] }])
  end

  it 'builds AUTH with the scramble as a UTF-8 string' do
    request = described_class::Auth.new(user: 'app', mechanism: 'chap-sha1', scramble: "\xff".b)
    scramble = request.body[0x21].last

    expect(scramble.encoding).to eq(Encoding::UTF_8)
    expect(encoded(request)).to eq([0x07, { 0x23 => 'app', 0x21 => ['chap-sha1', scramble] }])
  end

  it 'builds ID' do
    expect(encoded(described_class::Id.new(version: 3, features: [0, 1])))
      .to eq([0x49, { 0x54 => 3, 0x55 => [0, 1] }])
  end

  it 'builds EXECUTE from SQL text or a prepared statement id' do
    expect(encoded(described_class::Execute.new(statement: 'SELECT ?', bindings: [1])))
      .to eq([0x0b, { 0x40 => 'SELECT ?', 0x41 => [1] }])
    expect(encoded(described_class::Execute.new(statement: 7, bindings: [])))
      .to eq([0x0b, { 0x43 => 7, 0x41 => [] }])
  end

  it 'builds PREPARE for SQL text and for deallocation by statement id' do
    expect(encoded(described_class::Prepare.new(statement: 'SELECT 1'))).to eq([0x0d, { 0x40 => 'SELECT 1' }])
    expect(encoded(described_class::Prepare.new(statement: 7))).to eq([0x0d, { 0x43 => 7 }])
  end
end
