# frozen_string_literal: true

require 'socket'

RSpec.describe Tarantool::Client::Transport::FrameWriter do
  subject(:writer) { described_class.new(socket) }

  let(:pair) { UNIXSocket.pair }
  let(:socket) { pair.first }
  let(:peer) { pair.last }

  after { pair.each(&:close) }

  it 'writes the whole frame' do
    reader = Thread.new { peer.read(1_000_000) }
    writer.write('x' * 1_000_000, Tarantool::Client::Transport::Deadline.after(1))

    expect(reader.value.bytesize).to eq(1_000_000)
  end

  it 'raises TimeoutError when the peer does not read before the deadline' do
    deadline = Tarantool::Client::Transport::Deadline.after(0.05)

    expect { writer.write('x' * 8_000_000, deadline) }.to raise_error(Tarantool::TimeoutError)
  end
end
