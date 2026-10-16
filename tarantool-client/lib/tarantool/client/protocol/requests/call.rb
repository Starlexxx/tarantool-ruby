# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_CALL: invoke a stored or global Lua function.
        # @api private
        Call = Data.define(:function_name, :arguments) do
          def type = Constants::CALL
          def body = { Constants::FUNCTION_NAME => function_name, Constants::TUPLE => arguments }
        end
      end
    end
  end
end
