# frozen_string_literal: true

RSpec.describe Tarantool::Client::Protocol::Response do
  it 'exposes fields of a successful response' do
    response = described_class.new({ 0x00 => 0, 0x01 => 3, 0x05 => 12 }, { 0x30 => [1] })

    expect(response).to have_attributes(sync: 3, schema_version: 12, data: [1], error?: false, push?: false)
  end

  it 'decodes an error response with its stack' do
    stack = { 0x00 => [{ 0x00 => 'ClientError', 0x03 => 'Duplicate key', 0x05 => 3 }] }
    response = described_class.new({ 0x00 => 0x8003, 0x01 => 1 }, { 0x31 => 'Duplicate key', 0x52 => stack })

    expect(response).to have_attributes(
      error?: true, error_code: 3, error_message: 'Duplicate key',
      error_stack: [{ type: 'ClientError', message: 'Duplicate key', code: 3 }]
    )
  end

  it 'returns an empty stack when the server sent none' do
    response = described_class.new({ 0x00 => 0x8003, 0x01 => 1 }, { 0x31 => 'Duplicate key' })

    expect(response.error_stack).to eq([])
  end

  it 'detects pushes' do
    expect(described_class.new({ 0x00 => 0x80, 0x01 => 1 }, { 0x30 => ['hi'] })).to be_push
  end
end
