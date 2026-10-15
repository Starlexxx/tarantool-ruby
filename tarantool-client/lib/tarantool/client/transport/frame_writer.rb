# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Serializes whole-frame writes to a socket, each bounded by its own deadline.
      # Yields when a write is interrupted after part of the frame went out, because
      # the stream is corrupt from then on.
      class FrameWriter
        def initialize(socket)
          @socket = socket
          @lock = Mutex.new
        end

        # Async interrupts (Thread#raise, Timeout) are held until the blocking wait, so they
        # never land between a write and the update of the unsent remainder.
        def write(frame, deadline)
          @lock.synchronize do
            rest = frame
            Thread.handle_interrupt(Object => :on_blocking) do
              rest = write_some(rest, deadline) until rest.empty?
            end
          ensure
            yield if rest && !rest.empty? && rest.bytesize < frame.bytesize
          end
        end

        private

        def write_some(frame, deadline)
          written = @socket.write_nonblock(frame, exception: false)
          return frame.byteslice(written..) unless written == :wait_writable
          raise TimeoutError, 'socket write timed out' unless @socket.wait_writable(Deadline.remaining(deadline))

          frame
        end
      end
    end
  end
end
