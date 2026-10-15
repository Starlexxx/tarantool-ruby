# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Extensions
        # MP_ERROR: a box.error stack decoded into a BoxError chain.
        module Error
          module_function

          def unpack(payload)
            stack = Codec::FACTORY.load(payload, allow_unknown_ext: true).fetch(Constants::ERROR_STACK)
            Client::BoxError.from_stack(stack)
          end

          Extensions.register(Constants::MP_ERROR, Client::BoxError, unpacker: method(:unpack))
        end
      end
    end
  end
end
