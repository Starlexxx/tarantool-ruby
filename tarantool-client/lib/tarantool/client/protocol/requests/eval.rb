# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_EVAL: run a Lua chunk; arguments are available as `...`.
        Eval = Data.define(:expression, :arguments) do
          def type = Constants::EVAL
          def body = { Constants::EXPR => expression, Constants::TUPLE => arguments }
        end
      end
    end
  end
end
