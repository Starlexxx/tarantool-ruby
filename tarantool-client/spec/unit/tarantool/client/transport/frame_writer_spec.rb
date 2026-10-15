# frozen_string_literal: true

require 'socket'

RSpec.describe Tarantool::Client::Transport::FrameWriter do
  subject(:writer) { described_class.new(socket) }

  let(:pair) { UNIXSocket.pair }
  let(:socket) { pair.first }
  let(:peer) { pair.last }
  let(:partial_writes) { [] }

  after { pair.each(&:close) }

  def write(frame, timeout)
    writer.write(frame, Tarantool::Client::Transport::Deadline.after(timeout)) { partial_writes << frame.bytesize }
  end

  def fill_socket_buffer
    nil until socket.write_nonblock('x' * 4096, exception: false) == :wait_writable
  end

  def write_in_background(frame, timeout)
    Thread.new do
      write(frame, timeout)
    rescue Tarantool::TimeoutError
      :timed_out
    end
  end

  it 'bounds the wait for a write in progress by the deadline' do
    fill_socket_buffer
    blocked = write_in_background('x', 0.5)
    sleep 0.05
    started = Tarantool::Client::Transport::Deadline.now

    expect { write('y', 0.05) }.to raise_error(Tarantool::TimeoutError)
    expect(Tarantool::Client::Transport::Deadline.now - started).to be < 0.3
    expect(blocked.value).to eq(:timed_out)
  end

  it 'writes the whole frame' do
    reader = Thread.new { peer.read(1_000_000) }
    write('x' * 1_000_000, 1)

    expect(reader.value.bytesize).to eq(1_000_000)
    expect(partial_writes).to be_empty
  end

  it 'raises TimeoutError and reports a partial write when the peer stops reading mid-frame' do
    expect { write('x' * 8_000_000, 0.05) }.to raise_error(Tarantool::TimeoutError)
    expect(partial_writes).to eq([8_000_000])
  end

  it 'reports a partial write when an async interrupt arrives right after a write' do
    interrupt = Class.new(StandardError)
    socket.define_singleton_method(:write_nonblock) do |*args, **kwargs|
      singleton_class.remove_method(:write_nonblock)
      super(*args, **kwargs).tap { Thread.current.raise(interrupt) }
    end

    expect { write('x' * 8_000_000, nil) }.to raise_error(interrupt)
    expect(partial_writes).to eq([8_000_000])
  end

  it 'raises TimeoutError without reporting a partial write when nothing was sent' do
    fill_socket_buffer

    expect { write('x', 0.05) }.to raise_error(Tarantool::TimeoutError)
    expect(partial_writes).to be_empty
  end
end
