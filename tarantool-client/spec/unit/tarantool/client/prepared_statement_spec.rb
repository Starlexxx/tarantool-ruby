# frozen_string_literal: true

RSpec.describe Tarantool::Client::PreparedStatement do
  subject(:statement) { described_class.new(7, perform) }

  let(:performed) { [] }
  let(:perform) do
    lambda do |request, timeout:|
      performed << [request, timeout]
      Tarantool::Client::Protocol::Response.new({ 0x00 => 0, 0x01 => 1 }, { 0x42 => { 0x00 => 1 } })
    end
  end
  let(:requests) { Tarantool::Client::Protocol::Requests }

  it 'executes by statement id with bindings and timeout' do
    expect(statement.execute([1], timeout: 0.5).row_count).to eq(1)
    expect(performed).to eq([[requests::Execute.new(statement: 7, bindings: [1]), 0.5]])
  end

  it 'deallocates the statement on close' do
    expect(statement.close).to be_nil
    expect(performed).to eq([[requests::Prepare.new(statement: 7), nil]])
  end
end
