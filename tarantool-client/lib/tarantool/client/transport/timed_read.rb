# frozen_string_literal: true

module Tarantool
  class Client
    module Transport
      # Reads under one deadline for the whole read. IO#timeout bounds each read instead, so a peer
      # sending a byte at a time could stretch it to size times the timeout.
      # @api private
      module TimedRead
        module_function

        def read_exactly(io, size, deadline)
          data = String.new(capacity: size, encoding: Encoding::BINARY)
          while data.bytesize < size
            chunk = io.read_nonblock(size - data.bytesize, exception: false)
            raise EOFError, 'connection closed by server' if chunk.nil?

            chunk == :wait_readable ? wait_readable(io, deadline) : data << chunk
          end

          data
        end

        def wait_readable(io, deadline)
          raise TimeoutError, 'read timed out' unless io.wait_readable(Deadline.remaining(deadline))
        end
        private_class_method :wait_readable
      end
    end
  end
end
