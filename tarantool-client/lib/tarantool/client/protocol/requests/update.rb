# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_UPDATE: field operations on the tuple found by key.
        Update = Data.define(:space_id, :index_id, :key, :operations) do
          def type = Constants::UPDATE

          def body
            {
              Constants::SPACE_ID => space_id,
              Constants::INDEX_ID => index_id,
              Constants::KEY => key,
              Constants::TUPLE => operations
            }
          end
        end
      end
    end
  end
end
