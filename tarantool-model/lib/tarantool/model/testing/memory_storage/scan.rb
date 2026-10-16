# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # Tuples one select or count sees through an index: ordered by the index key, then the primary key (le and
        # lt walk backwards), filtered by the key prefix condition, then continued strictly past `after`.
        # @api private
        class Scan
          MATCHES = {
            eq: :zero?.to_proc, ge: ->(result) { result >= 0 }, gt: :positive?.to_proc,
            le: ->(result) { result <= 0 }, lt: :negative?.to_proc, all: ->(_result) { true }
          }.freeze
          DESCENDING = %i[le lt].freeze
          HASH_ITERATORS = %i[eq gt all].freeze

          def initialize(space_info, index)
            @space_info = space_info
            @index = index
            @primary = space_info.primary_index
          end

          def call(tuples, key:, iterator:, after:)
            match = matcher(iterator)
            raise Violation.key_part_count(@index.parts.size, key.size) if key.size > @index.parts.size

            check_hash!(key, iterator, after)
            sign = sign_for(iterator)
            found = matching(sorted(tuples, sign), key, match)

            after ? strictly_after(found, after, sign) : found
          end

          private

          # memtx starts a tree :all at the key, like :ge; a hash :all ignores the key.
          def matcher(iterator)
            return MATCHES[:ge] if iterator == :all && @index.type == 'tree'

            MATCHES.fetch(iterator) { raise ArgumentError, "unsupported iterator #{iterator.inspect}" }
          end

          def sign_for(iterator)
            DESCENDING.include?(iterator) ? -1 : 1
          end

          def matching(tuples, key, match)
            tuples.select { |tuple| key.empty? || match.call(compare_key(tuple, key)) }
          end

          def strictly_after(tuples, after, sign)
            tuples.select { |tuple| Order.compare(position(tuple), position(after)) * sign == 1 }
          end

          def sorted(tuples, sign)
            tuples.sort { |left, right| Order.compare(position(left), position(right)) * sign }
          end

          def compare_key(tuple, key)
            Order.compare(@index.parts.first(key.size).map { |part| tuple[part.fieldno] }, key)
          end

          def position(tuple)
            (@index.parts + @primary.parts).map { |part| tuple[part.fieldno] }
          end

          def check_hash!(key, iterator, after)
            return unless @index.type == 'hash'
            raise Violation.partial_hash_key(@index.parts.size, key.size) if partial?(key)
            raise Violation.iterator(@index.name, @space_info.name) unless HASH_ITERATORS.include?(iterator)
            raise Violation.pagination(@index.name, @space_info.name) if after
          end

          def partial?(key)
            !key.empty? && key.size != @index.parts.size
          end
        end
      end
    end
  end
end
