# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_SELECT: index lookup or scan. `after` continues past a tuple (keyset pagination, 2.11+).
        Select = Data.define(:space_id, :index_id, :key, :limit, :offset, :iterator, :after) do
          def initialize(iterator:, after: nil, **)
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
            }.tap { |body| body[Constants::AFTER_TUPLE] = after unless after.nil? }
          end
        end
      end
    end
  end
end
