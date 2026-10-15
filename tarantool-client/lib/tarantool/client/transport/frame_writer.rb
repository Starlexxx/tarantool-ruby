# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Serializes whole-frame writes to a socket, each bounded by its own deadline.
      class FrameWriter
        def initialize(socket)
          @socket = socket
          @lock = Mutex.new
        end

        def write(frame, deadline)
          @lock.synchronize { write_all(frame, deadline) }
        end

        private

        def write_all(frame, deadline)
          until frame.empty?
            written = @socket.write_nonblock(frame, exception: false)
            next frame = frame.byteslice(written..) unless written == :wait_writable
            raise TimeoutError, 'socket write timed out' unless @socket.wait_writable(Deadline.remaining(deadline))
          end
        end
      end
    end
  end
end
