# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_SELECT: index lookup or scan.
        Select = Data.define(:space_id, :index_id, :key, :limit, :offset, :iterator) do
          def initialize(iterator:, **)
            raise ArgumentError, "unknown iterator: #{iterator.inspect}" unless Constants::ITERATORS.key?(iterator)

            super
          end

          def type = Constants::SELECT

          def body
            {
              Constants::SPACE_ID => space_id,
              Constants::INDEX_ID => index_id,
              Constants::LIMIT => limit,
              Constants::OFFSET => offset,
              Constants::ITERATOR => Constants::ITERATORS.fetch(iterator),
              Constants::KEY => key
            }
          end
        end
      end
    end
  end
end
