# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # Storage::Crud behaviour: no schema check, count, no transactions, no tuple on single-row results, no
        # sequences, bucket_id filled in, and the tarantool-crud error class of each operation.
        # @api private
        class CrudMode
          BUCKET_ID = 'bucket_id'
          BUCKET_COUNT = 30_000
          FLATTEN = 'Failed to flatten object: FlattenError: Object is specified in bad format: FlattenError: ' \
                    'Field "%s" isn\'t nullable (set skip_nullability_check_on_flatten option to true to skip check)'

          def verify(**) = nil

          def count! = nil

          def transaction!
            raise NotSupportedError, 'crud has no interactive transactions'
          end

          def sequences? = false

          def supports_transactions? = false

          def get(space, key)
            parts = space.info.primary_index.parts.size
            raise Violation.exact_match(parts, key.size) unless key.size == parts

            space.get(key)
          end

          def to_tuple(space, attributes)
            tuple = space.info.to_tuple(attributes)
            fieldno = space.info.fields.index { |field| field.name == BUCKET_ID }
            tuple[fieldno] ||= bucket(space, tuple) if fieldno

            tuple
          end

          def row(space, tuple, single:)
            Row.new(attributes: space.info.to_hash(tuple), tuple: single ? nil : tuple)
          end

          # Without a condition crud scans the primary index. With one, crud reads a name that is not an index as a
          # field name and filters by that field; this returns nothing instead, as crud does for a name that is
          # neither.
          def scan(space, index:, key:, iterator:, after:)
            return space.scan(index: nil, key: [], iterator: :all, after:) if iterator == :all || key.empty?
            return [] unless space.index?(index)

            space.scan(index:, key:, iterator:, after:)
          end

          def error(violation, operation)
            raise Error, "tarantool-crud is not loaded; require 'tarantool/crud'" unless defined?(Tarantool::Crud)

            Tarantool::Crud.const_get("#{operation.capitalize}Error").new(message(violation, operation))
          end

          private

          def bucket(space, tuple)
            key = space.info.primary_index.parts.map { |part| tuple[part.fieldno] }

            (Zlib.crc32(Marshal.dump(key)) % BUCKET_COUNT) + 1
          end

          def message(violation, operation)
            return %(Space "#{violation.subject}" doesn't exist) if violation.kind == :space
            return format(FLATTEN, violation.subject) if violation.kind == :nil_field && operation == :insert

            "Failed to #{operation}: #{violation.message}"
          end
        end
      end
    end
  end
end
