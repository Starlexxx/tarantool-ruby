# frozen_string_literal: true

RSpec.describe Tarantool::Client, :integration do
  subject(:client) { described_class.new(ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301')) }

  let(:rows) { Array.new(6) { |i| [i + 1, (i + 1) % 3 * 10, "n#{i + 1}", { 'x' => "v#{i + 1}" }] } }

  before do
    client.eval(<<~LUA)
      if box.space.page_items then box.space.page_items:drop() end
      local s = box.schema.space.create('page_items', {format = {
        {name = 'id', type = 'unsigned'}, {name = 'grp', type = 'unsigned'},
        {name = 'name', type = 'string'}, {name = 'meta', type = 'map', is_nullable = true}}})
      s:create_index('primary', {parts = {'id'}})
      s:create_index('grp', {parts = {'grp'}, unique = false})
      s:create_index('by_name', {type = 'hash', parts = {'name'}})
      s:create_index('meta_x', {
        parts = {{field = 'meta', path = 'x', type = 'string', is_nullable = true}},
        unique = false,
      })
    LUA
    rows.each { |row| client.insert(:page_items, row) }
  end

  after do
    client.eval('if box.space.page_items then box.space.page_items:drop() end')
    client.close
  end

  def page(index, key, iterator, size)
    pages = [client.select(:page_items, key, index:, iterator:, limit: size)]
    until pages.last.size < size
      pages << client.select(:page_items, key, index:, iterator:, limit: size, after: pages.last.last)
    end

    pages
  end

  describe '#space_info' do
    it 'returns the format of the space' do
      expect(client.space_info(:page_items).fields.map(&:name)).to eq(%w[id grp name meta])
      expect(client.space_info(:page_items).fields.last.is_nullable).to be(true)
    end

    it 'returns indexes in id order with their parts' do
      indexes = client.space_info(:page_items).indexes

      expect(indexes.keys).to eq(%w[primary grp by_name meta_x])
      expect(indexes['by_name']).to have_attributes(type: 'hash', unique: true)
      expect(indexes['meta_x'].parts.first).to have_attributes(fieldno: 3, name: 'meta', path: 'x', is_nullable: true)
    end
  end

  describe 'select after a tuple' do
    it 'pages through the primary index' do
      expect(page(:primary, [], :all, 4).flatten(1)).to eq(rows)
    end

    it 'pages through a non-unique index without losing equal keys' do
      expect(page(:grp, [10], :ge, 2).flatten(1)).to eq(client.select(:page_items, [10], index: :grp, iterator: :ge))
    end

    it 'pages in descending order with :lt' do
      expect(page(:grp, [20], :lt, 3).flatten(1)).to eq(client.select(:page_items, [20], index: :grp, iterator: :lt))
    end

    it 'raises ServerError for a HASH index' do
      expect { client.select(:page_items, [], index: :by_name, iterator: :all, after: rows.first) }
        .to raise_error(Tarantool::ServerError) { |error| expect(error.code).to eq(112) }
    end
  end

  describe 'inside a transaction' do
    it 'returns space info and selects after a tuple' do
      result = client.transaction do |tx|
        [tx.space_info(:page_items).id, tx.select(:page_items, [], iterator: :all, limit: 2, after: rows[1])]
      end

      expect(result).to eq([client.space_info(:page_items).id, rows[2, 2]])
    end
  end
end
