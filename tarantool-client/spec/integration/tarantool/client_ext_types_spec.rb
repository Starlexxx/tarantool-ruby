# frozen_string_literal: true

RSpec.describe Tarantool::Client, :integration do
  subject(:client) { described_class.new(uri) }

  let(:uri) { ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301') }

  def prelude
    "local decimal, uuid, datetime = require('decimal'), require('uuid'), require('datetime')\n"
  end

  def decimal
    BigDecimal('-12.345')
  end

  def uuid
    Tarantool::Client::UUID.new('f81d4fae-7dec-11d0-a765-00a0c91e6bf6')
  end

  def time
    Time.at(1_710_061_200, 123_456_789, :nsec, in: '+03:00')
  end

  def interval
    Tarantool::Client::Interval.new(year: 1, month: -2, day: 4, nsec: 8, adjust: :last)
  end

  def server_comparison
    <<~LUA
      local d, u, t, i = ...
      local expected = datetime.interval.new{year = 1, month = -2, day = 4, nsec = 8, adjust = 'last'}
      return decimal.is_decimal(d) and d == decimal.new('-12.345'),
        uuid.is_uuid(u) and u == uuid.fromstr('f81d4fae-7dec-11d0-a765-00a0c91e6bf6'),
        datetime.is_datetime(t) and t == datetime.new{year = 2024, month = 3, day = 10, hour = 12,
          nsec = 123456789, tzoffset = 180},
        tostring(i) == tostring(expected) and i.adjust == expected.adjust
    LUA
  end

  def lua(code, args = [])
    client.eval(prelude + code, args)
  end

  before do
    client.eval(<<~LUA)
      if box.space.ext_values then box.space.ext_values:drop() end
      local space = box.schema.space.create('ext_values', {format = {
        {name = 'id', type = 'unsigned'}, {name = 'decimal', type = 'decimal'}, {name = 'uuid', type = 'uuid'},
        {name = 'datetime', type = 'datetime'}, {name = 'interval', type = 'any'},
      }})
      space:create_index('pk')
    LUA
  end

  after { client.close }

  it 'round-trips every ext type through a typed space' do
    client.insert(:ext_values, [1, decimal, uuid, time, interval])

    expect(client.select(:ext_values, 1)).to eq([[1, decimal, uuid, time, interval]])
  end

  it 'keeps nanoseconds and the offset of a stored datetime' do
    client.insert(:ext_values, [1, decimal, uuid, time, interval])

    expect(client.select(:ext_values, 1).first[3]).to have_attributes(nsec: 123_456_789, utc_offset: 10_800)
  end

  it 'refuses a plain uuid string for a uuid field' do
    expect { client.insert(:ext_values, [1, decimal, uuid.to_s, time, interval]) }
      .to raise_error(Tarantool::ServerError, /uuid/)
  end

  it 'decodes values built in Lua' do
    values = lua(<<~LUA)
      return decimal.new('-12.345'), uuid.fromstr('f81d4fae-7dec-11d0-a765-00a0c91e6bf6'),
        datetime.new{year = 2024, month = 3, day = 10, hour = 12, nsec = 123456789, tzoffset = 180},
        datetime.interval.new{year = 1, month = -2, day = 4, nsec = 8, adjust = 'last'}
    LUA

    expect(values).to eq([decimal, uuid, time, interval])
  end

  it 'decodes a datetime with a named zone through its offset' do
    moscow = lua("return datetime.new{year = 2024, month = 3, day = 10, tz = 'MSK'}").first

    expect(moscow).to eq(Time.new(2024, 3, 10, 0, 0, 0, '+03:00')).and have_attributes(utc_offset: 10_800)
  end

  it 'sends values the server sees as the matching Lua values' do
    expect(lua(server_comparison, [decimal, uuid, time, interval])).to eq([true, true, true, true])
  end
end
