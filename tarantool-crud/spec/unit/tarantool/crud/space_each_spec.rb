# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Space do
  subject(:users) { Tarantool::Crud::Client.new(transport).space(:users) }

  let(:transport) { FakeCaller.new([crud_result([1, 'a'], [2, 'b']), nil], [crud_result([3, 'c']), nil]) }

  it 'yields rows across batches' do
    expect { |probe| users.each({ id: 1.. }, batch_size: 2, &probe) }
      .to yield_successive_args({ id: 1, name: 'a' }, { id: 2, name: 'b' }, { id: 3, name: 'c' })
  end

  it 'pages with first and the last tuple of the previous batch' do
    users.each(batch_size: 2, timeout: 1) { nil }

    expect(transport.requests.map(&:arguments)).to eq(
      [['users', nil, { timeout: 1, first: 2 }], ['users', nil, { timeout: 1, first: 2, after: [2, 'b'] }]]
    )
  end

  it 'fetches batches lazily without a block' do
    expect(users.each(batch_size: 2).first(1)).to eq([{ id: 1, name: 'a' }])
    expect(transport.requests.size).to eq(1)
  end

  it 'reads batches of 1000 by default' do
    users.each { nil }

    expect(transport.requests.map { |request| request.arguments.last }).to eq([{ first: 1000 }])
  end
end
