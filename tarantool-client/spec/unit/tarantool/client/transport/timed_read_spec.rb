# frozen_string_literal: true

require 'socket'

RSpec.describe Tarantool::Client::Transport::TimedRead do
  let(:pair) { UNIXSocket.pair }
  let(:reader) { pair.first }
  let(:writer) { pair.last }

  def deadline(seconds) = Tarantool::Client::Transport::Deadline.after(seconds)

  after { pair.each(&:close) }

  it 'collects the bytes across several writes' do
    sender = Thread.new { %w[ab cd].each { |part| writer.write(part).then { sleep 0.01 } } }

    expect(described_class.read_exactly(reader, 4, deadline(1))).to eq('abcd')
  ensure
    sender.join
  end

  it 'raises TimeoutError once the deadline passes mid-read' do
    writer.write('a')

    expect { described_class.read_exactly(reader, 2, deadline(0.05)) }.to raise_error(Tarantool::TimeoutError)
  end

  it 'raises EOFError when the peer closes early' do
    writer.write('a')
    writer.close

    expect { described_class.read_exactly(reader, 2, deadline(1)) }.to raise_error(EOFError)
  end
end
