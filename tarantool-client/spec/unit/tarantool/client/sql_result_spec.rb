# frozen_string_literal: true

RSpec.describe Tarantool::Client::SqlResult do
  def result(body)
    described_class.from_response(Tarantool::Client::Protocol::Response.new({ 0x00 => 0, 0x01 => 1 }, body))
  end

  it 'reads rows and column names of a query' do
    metadata = [{ 0x00 => 'id', 0x01 => 'integer' }, { 0x00 => 'name', 0x01 => 'string' }]

    expect(result({ 0x32 => metadata, 0x30 => [[1, 'a']] }))
      .to have_attributes(rows: [[1, 'a']], columns: %w[id name], row_count: nil, autoincrement_ids: [])
  end

  it 'reads the row count and generated ids of a data change' do
    expect(result({ 0x42 => { 0x00 => 2, 0x01 => [1, 2] } }))
      .to have_attributes(rows: [], columns: [], row_count: 2, autoincrement_ids: [1, 2])
  end

  it 'returns no generated ids when the server sent none' do
    expect(result({ 0x42 => { 0x00 => 1 } }).autoincrement_ids).to eq([])
  end
end
