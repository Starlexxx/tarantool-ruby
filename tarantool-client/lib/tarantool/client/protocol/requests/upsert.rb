# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_UPSERT: insert the tuple or apply operations to the existing one.
        Upsert = Data.define(:space_id, :tuple, :operations) do
          def type = Constants::UPSERT

          def body
            { Constants::SPACE_ID => space_id, Constants::TUPLE => tuple, Constants::OPS => operations }
          end
        end
      end
    end
  end
end
