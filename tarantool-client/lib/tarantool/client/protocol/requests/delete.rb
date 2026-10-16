# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_DELETE: remove the tuple found by key.
        # @api private
        Delete = Data.define(:space_id, :index_id, :key) do
          def type = Constants::DELETE

          def body
            { Constants::SPACE_ID => space_id, Constants::INDEX_ID => index_id, Constants::KEY => key }
          end
        end
      end
    end
  end
end
