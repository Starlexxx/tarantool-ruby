# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # Rows of one space keyed by primary key, with the checks Tarantool makes on write. Values are deep-copied
        # in and out, and a stored tuple is never changed in place, so a snapshot is a shallow copy of the rows.
        # @api private
        class Space
          attr_reader :info, :layout, :mapping

          def initialize(info, sequence:)
            @info = info
            @layout = Storage::Box::Layout.new(info)
            @mapping = TupleMapping.new(info)
            @primary = info.primary_index
            @sequence_fieldno = sequence && @primary.parts.first.fieldno
            @counter = 0
            @required = required_fieldnos
            @rows = {}
          end

          def get(key)
            copy(@rows[copy(key)])
          end

          def insert(tuple)
            tuple = copy(tuple)
            advance_sequence(tuple)

            store(tuple, replacing: nil)
          end

          def update(key, operations)
            key = copy(key)
            current = @rows[key]
            return unless current

            updated = Operations.new(@info).apply(current, copy(operations))
            raise Violation.primary_key_update(@info.name) unless key_of(updated, @primary) == key

            store(updated, replacing: key)
          end

          def delete(key)
            copy(@rows.delete(copy(key)))
          end

          def scan(index:, key:, iterator:, after:)
            Scan.new(@info, index_info(index)).call(@rows.values, key: copy(key), iterator:, after: copy(after))
                .map { |tuple| copy(tuple) }
          end

          def index?(name)
            name.nil? || name.is_a?(Integer) || @info.indexes.key?(name.to_s)
          end

          def snapshot
            @rows.dup
          end

          def restore(rows)
            @rows = rows
          end

          private

          def index_info(name)
            return @primary if name.nil?

            found = name.is_a?(Integer) ? @info.indexes.each_value.find { |index| index.id == name } : by_name(name)
            found || raise(Violation.unknown_index(name, @info.name))
          end

          def by_name(name)
            @info.indexes[name.to_s]
          end

          def store(tuple, replacing:)
            check_nils(tuple)
            check_unique(tuple, replacing)
            @rows.delete(replacing) if replacing
            @rows[key_of(tuple, @primary)] = tuple

            copy(tuple)
          end

          def check_nils(tuple)
            @required.each do |fieldno|
              raise Violation.nil_field(fieldno, @info.fields[fieldno]) if tuple[fieldno].nil?
            end
          end

          def check_unique(tuple, replacing)
            @info.indexes.each_value.select(&:unique).each do |index|
              key = key_of(tuple, index)
              next if key.include?(nil)

              _, old = @rows.find { |row_key, row| row_key != replacing && key_of(row, index) == key }
              next unless old

              raise RecordNotUnique, duplicate_key_message(index, old, tuple)
            end
          end

          def duplicate_key_message(index, old, tuple)
            "Duplicate key exists in unique index \"#{index.name}\" in space \"#{@info.name}\" with old tuple - " \
              "#{old.inspect} and new tuple - #{tuple.inspect}"
          end

          def advance_sequence(tuple)
            return unless @sequence_fieldno

            value = tuple[@sequence_fieldno]
            if value.nil?
              tuple[@sequence_fieldno] = @counter += 1
            elsif value.is_a?(Integer)
              @counter = [@counter, value].max
            end
          end

          def required_fieldnos
            strict_parts = @info.indexes.each_value.flat_map(&:parts).reject(&:is_nullable).map(&:fieldno)

            @info.fields.each_index.select do |fieldno|
              field = @info.fields[fieldno]
              strict_parts.include?(fieldno) || !(field.is_nullable || field.type == 'any')
            end
          end

          def key_of(tuple, index)
            index.parts.map { |part| tuple[part.fieldno] }
          end

          # Codec is @api private in tarantool-client, but released together with tarantool-model in this
          # monorepo; only the wire round trip turns Symbols into Strings and rejects values Tarantool can't store.
          def copy(value)
            value && Client::Protocol::Codec::FACTORY.load(Client::Protocol::Codec::FACTORY.dump(value))
          end
        end
      end
    end
  end
end
