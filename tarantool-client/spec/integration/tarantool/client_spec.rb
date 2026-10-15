# frozen_string_literal: true

RSpec.describe Tarantool::Client, :integration do
  subject(:client) { described_class.new(uri) }

  let(:uri) { ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301') }

  before { client.eval('box.space.users:truncate()') }
  after { client.close }

  it 'pings' do
    expect(client.ping).to be(true)
  end

  it 'inserts and selects by primary and secondary index' do
    client.insert(:users, [1, 'a@b.c', 0])

    expect(client.select(:users, 1)).to eq([[1, 'a@b.c', 0]])
    expect(client.select(:users, 'a@b.c', index: :email)).to eq([[1, 'a@b.c', 0]])
  end

  it 'updates, upserts, replaces and deletes' do
    client.insert(:users, [1, 'a@b.c', 0])

    expect(client.update(:users, 1, [['+', 2, 5]])).to eq([1, 'a@b.c', 5])
    client.upsert(:users, [1, 'a@b.c', 0], [['+', 2, 1]])
    expect(client.replace(:users, [1, 'x@y.z', 7])).to eq([1, 'x@y.z', 7])
    expect(client.delete(:users, 1)).to eq([1, 'x@y.z', 7])
  end

  it 'calls functions and evaluates Lua' do
    expect(client.call('echo', [1, 'a'])).to eq([1, 'a'])
    expect(client.eval('return ...', [2, 3])).to eq([2, 3])
  end

  it 'raises ServerError with the Tarantool error code on duplicate key' do
    client.insert(:users, [1, 'a@b.c', 0])

    expect { client.insert(:users, [1, 'a@b.c', 0]) }
      .to raise_error(Tarantool::ServerError) { |error| expect(error.code).to eq(3) }
  end

  it 'raises SchemaError for an unknown space' do
    expect { client.select(:missing) }.to raise_error(Tarantool::SchemaError)
  end

  it 'sees spaces created after connect' do
    client.eval("box.schema.space.create('scratch', {if_not_exists = true}):create_index('pk', {if_not_exists = true})")

    expect(client.select(:scratch)).to eq([])
  ensure
    client.eval('if box.space.scratch then box.space.scratch:drop() end')
  end

  context 'when another client recreates a space under a new id' do
    let(:recreate_scratch) do
      <<~LUA
        box.space.scratch:drop()
        box.schema.space.create('decoy', {id = 600}):create_index('pk')
        box.space.decoy:insert({1, 'decoy'})
        box.schema.space.create('scratch', {id = 601}):create_index('pk')
        box.space.scratch:insert({1, 'scratch'})
      LUA
    end

    before do
      client.eval("box.schema.space.create('scratch', {id = 600}):create_index('pk')")
      client.select(:scratch)
    end

    after do
      client.eval('for _, s in ipairs({"scratch", "decoy"}) do if box.space[s] then box.space[s]:drop() end end')
    end

    it 'reads the recreated space instead of whatever took its old id' do
      other = described_class.new(uri)
      other.eval(recreate_scratch)
      other.close

      expect(client.select(:scratch)).to eq([[1, 'scratch']])
    end
  end

  it 'times out a slow request and keeps the connection usable' do
    expect { client.eval("require('fiber').sleep(0.5)", timeout: 0.05) }.to raise_error(Tarantool::TimeoutError)
    expect(client.ping).to be(true)
  end

  it 'serves concurrent requests over one connection' do
    results = Array.new(10) { |i| Thread.new { client.call('echo', [i]) } }.map(&:value)

    expect(results).to eq(Array.new(10) { |i| [i] })
  end

  it 'rejects a wrong password' do
    expect { described_class.new(uri.sub('secret', 'wrong')) }.to raise_error(Tarantool::AuthenticationError)
  end
end
