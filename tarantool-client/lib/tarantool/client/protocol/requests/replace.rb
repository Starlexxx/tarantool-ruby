# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_REPLACE: insert or overwrite by primary key.
        # @api private
        Replace = Data.define(:space_id, :tuple) do
          def type = Constants::REPLACE
          def body = { Constants::SPACE_ID => space_id, Constants::TUPLE => tuple }
        end
      end
    end
  end
end
