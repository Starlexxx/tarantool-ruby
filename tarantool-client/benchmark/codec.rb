# frozen_string_literal: true

# Encode/decode throughput of the client's IPROTO codec (msgpack with the Tarantool extension types) against
# plain MessagePack, for a plain tuple and one with Decimal, UUID and Datetime fields:
#   bundle exec ruby -Ilib benchmark/codec.rb
# ITERATIONS sets the number of tuples per case.

require 'tarantool/client'
require_relative 'measure'

ITERATIONS = Integer(ENV.fetch('ITERATIONS', 200_000))

PLAIN = [1, 'alice', 'alice@example.com', 42, 3.14, true, nil, %w[a b c], { 'k' => 'v' }, 'x' * 64].freeze
TYPED = [1, 'alice', BigDecimal('123.45'), Tarantool::Client::UUID.new('6ba7b810-9dad-11d1-80b4-00c04fd430c8'),
         Time.utc(2026, 10, 17, 12, 0, 0), 3.14, true, %w[a b c], { 'k' => 'v' }, 'x' * 64].freeze

# A request that carries one tuple, the shape of INSERT.
Request = Data.define(:tuple) do
  def type = Tarantool::Client::Protocol::Constants::INSERT

  def body
    { Tarantool::Client::Protocol::Constants::SPACE_ID => 512, Tarantool::Client::Protocol::Constants::TUPLE => tuple }
  end
end

FACTORY = Tarantool::Client::Protocol::Codec::FACTORY
CODEC = Tarantool::Client::Protocol::Codec

def rate(iterations, operation)
  started = Measure.now
  iterations.times { operation.call }

  iterations / (Measure.now - started)
end

def frame(tuple) = CODEC.encode(Request.new(tuple), sync: 1).byteslice(5..)

def cases(name, tuple)
  plain_packed = MessagePack.pack(tuple)
  frame = frame(tuple)
  {
    "#{name} MessagePack.pack" => -> { MessagePack.pack(tuple) },
    "#{name} Codec.encode" => -> { CODEC.encode(Request.new(tuple), sync: 1) },
    "#{name} MessagePack.unpack" => -> { MessagePack.unpack(plain_packed) },
    "#{name} Codec.decode" => -> { CODEC.decode(frame) }
  }
end

def typed_cases(name, tuple)
  packed = FACTORY.dump(tuple)
  frame = frame(tuple)
  {
    "#{name} Codec.encode" => -> { CODEC.encode(Request.new(tuple), sync: 1) },
    "#{name} factory dump" => -> { FACTORY.dump(tuple) },
    "#{name} factory load" => -> { FACTORY.load(packed) },
    "#{name} Codec.decode" => -> { CODEC.decode(frame) }
  }
end

puts "#{RUBY_DESCRIPTION} | msgpack #{MessagePack::VERSION} | tarantool-client #{Tarantool::Client::VERSION}"
cases('plain', PLAIN).merge(typed_cases('typed', TYPED)).each do |name, operation|
  rate(ITERATIONS / 10, operation)
  puts format('%-28<name>s %10<rate>.0f ops/s', name:, rate: rate(ITERATIONS, operation))
end
