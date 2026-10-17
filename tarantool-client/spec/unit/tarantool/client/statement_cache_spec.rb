# frozen_string_literal: true

RSpec.describe Tarantool::Client::StatementCache do
  subject(:cache) { described_class.new(2) }

  it 'prepares on a miss and reuses the id on a hit' do
    prepared = 0
    first = cache.id_for('SELECT 1') { prepared += 1 }
    second = cache.id_for('SELECT 1') { prepared += 1 }

    expect([first, second, prepared]).to eq([[1, nil], [1, nil], 1])
  end

  it 'evicts the least recently used statement at the limit' do
    cache.id_for('a') { 1 }
    cache.id_for('b') { 2 }
    cache.id_for('a') { 3 }

    expect(cache.id_for('c') { 4 }).to eq([4, 2])
  end

  it 'returns an id stored meanwhile for the same sql as evicted' do
    cache.id_for('a') { cache.id_for('a') { 1 }.first + 1 }

    expect(cache.id_for('a') { 9 }).to eq([2, nil])
  end

  it 'forgets one statement and clears all of them' do
    cache.id_for('a') { 1 }
    cache.id_for('b') { 2 }

    expect([cache.forget('a'), cache.forget('nope'), cache.clear, cache.clear]).to eq([1, nil, [2], []])
  end
end
