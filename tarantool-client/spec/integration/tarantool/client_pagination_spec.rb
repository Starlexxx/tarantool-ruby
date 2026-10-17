# frozen_string_literal: true

RSpec.describe Tarantool::Client, :integration do
  subject(:client) { described_class.new(uri) }

  let(:uri) { ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301') }
  let(:rows) { Array.new(5) { |i| [i + 1, i % 2] } }

  before do
    client.eval(<<~LUA)
      if box.space.position_items then box.space.position_items:drop() end
      local s = box.schema.space.create('position_items', {format = {
        {name = 'id', type = 'unsigned'}, {name = 'grp', type = 'unsigned'}}})
      s:create_index('primary', {parts = {'id'}})
      s:create_index('grp', {parts = {'grp'}, unique = false})
    LUA
    rows.each { |row| client.insert(:position_items, row) }
  end

  after do
    client.eval('if box.space.position_items then box.space.position_items:drop() end')
    client.close
  end

  def page(caller, after, **options)
    caller.select(:position_items, [], index: :grp, iterator: :all, limit: 2, fetch_position: true, after:, **options)
  end

  def pages(caller, **options)
    pages = [page(caller, nil, **options)]
    pages << page(caller, pages.last.position, **options) until pages.last.empty?

    pages
  end

  it 'walks an index by positions until an empty page' do
    walked = pages(client)

    expect(walked.map(&:size)).to eq([2, 2, 1, 0])
    expect(walked.flat_map(&:tuples)).to eq(client.select(:position_items, [], index: :grp, iterator: :all))
  end

  it 'ends with a page without a position' do
    expect(pages(client).map(&:position)).to end_with(nil)
  end

  it 'continues from a position inside a transaction' do
    first = client.select(:position_items, [], index: :grp, iterator: :all, limit: 2, fetch_position: true)

    second = client.transaction do |tx|
      tx.select(:position_items, [], index: :grp, iterator: :all, limit: 2, after: first.position, as: :hash)
    end

    expect(second).to eq([{ id: 5, grp: 0 }, { id: 2, grp: 1 }])
  end

  it 'pages through a pool' do
    pool = Tarantool::Client::Pool.new([uri])

    expect(pages(pool, mode: :any).flat_map(&:tuples)).to eq(rows.sort_by { |id, grp| [grp, id] })
  ensure
    pool&.close
  end
end
