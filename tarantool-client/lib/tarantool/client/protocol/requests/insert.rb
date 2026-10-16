# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_INSERT: fails on duplicate primary key.
        # @api private
        Insert = Data.define(:space_id, :tuple) do
          def type = Constants::INSERT
          def body = { Constants::SPACE_ID => space_id, Constants::TUPLE => tuple }
        end
      end
    end
  end
end
