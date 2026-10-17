# frozen_string_literal: true

RSpec.describe Tarantool::Client::Protocol::Response do
  it 'exposes fields of a successful response' do
    response = described_class.new({ 0x00 => 0, 0x01 => 3, 0x05 => 12 }, { 0x30 => [1] })

    expect(response).to have_attributes(sync: 3, schema_version: 12, data: [1], error?: false, push?: false)
  end

  it 'exposes the position of a page and nil without one' do
    with = described_class.new({ 0x00 => 0, 0x01 => 1 }, { 0x30 => [[1]], 0x35 => 'pos' })
    without = described_class.new({ 0x00 => 0, 0x01 => 1 }, { 0x30 => [] })

    expect([with.position, without.position]).to eq(['pos', nil])
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

  it 'exposes the key and value of an event' do
    response = described_class.new({ 0x00 => 0x4c, 0x01 => 0 }, { 0x57 => 'box.status', 0x58 => { 'is_ro' => false } })

    expect(response).to have_attributes(event?: true, push?: false, event_key: 'box.status',
                                        event_data: { 'is_ro' => false })
  end

  it 'returns nil event data for a key that was never broadcast' do
    response = described_class.new({ 0x00 => 0x4c, 0x01 => 0 }, { 0x57 => 'app.state' })

    expect(response.event_data).to be_nil
  end

  it 'does not treat replies as events' do
    expect(described_class.new({ 0x00 => 0, 0x01 => 1 }, {})).not_to be_event
  end
end
