# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Extensions
        # MP_ERROR: a box.error stack decoded into a BoxError chain. Error fields may hold further MP_ERRORs,
        # each decoded by a nested call; the depth sits in fiber-local storage, so concurrent decoders never share it.
        # @api private
        module Error
          MAX_DEPTH = 16
          DEPTH_KEY = :tarantool_mp_error_depth

          module_function

          def unpack(payload)
            depth = Thread.current[DEPTH_KEY] || 0
            raise ProtocolError, "MP_ERROR nested deeper than #{MAX_DEPTH} levels" if depth >= MAX_DEPTH

            Thread.current[DEPTH_KEY] = depth + 1
            stack = Codec::FACTORY.load(payload, allow_unknown_ext: true).fetch(Constants::ERROR_STACK)

            Client::BoxError.from_stack(stack)
          ensure
            Thread.current[DEPTH_KEY] = depth
          end

          Extensions.register(Constants::MP_ERROR, Client::BoxError, unpacker: method(:unpack))
        end
      end
    end
  end
end
