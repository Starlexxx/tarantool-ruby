# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Requests
        # IPROTO_SELECT: index lookup or scan. `after` continues past a tuple (Array) or a position (String, from
        # a response asked with `fetch_position`); keyset pagination, 2.11+.
        # @api private
        Select = Data.define(:space_id, :index_id, :key, :limit, :offset, :iterator, :after, :fetch_position) do
          def initialize(iterator:, after: nil, fetch_position: false, **)
            raise ArgumentError, "unknown iterator: #{iterator.inspect}" unless Constants::ITERATORS.key?(iterator)
            unless after.nil? || after.is_a?(Array) || after.is_a?(String)
              raise ArgumentError, "after: expected a tuple (Array) or a position (String), got #{after.inspect}"
            end

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
              Constants::KEY => key,
              **pagination
            }
          end

          private

          def pagination
            keys = {}
            keys[after.is_a?(String) ? Constants::AFTER_POSITION : Constants::AFTER_TUPLE] = after unless after.nil?
            keys[Constants::FETCH_POSITION] = true if fetch_position

            keys
          end
        end
      end
    end
  end
end
