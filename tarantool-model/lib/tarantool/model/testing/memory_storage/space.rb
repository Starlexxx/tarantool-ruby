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
            @sequence = sequence && @primary.parts.first.fieldno
            @counter = 0
            @required = required_fieldnos
            @rows = {}
          end

          def get(key)
            copy(@rows[key])
          end

          def insert(tuple)
            tuple = copy(tuple)
            advance_sequence(tuple)

            store(tuple, replacing: nil)
          end

          def update(key, operations)
            current = @rows[key]
            return unless current

            updated = Operations.new(@info).apply(current, copy(operations))
            raise Violation.primary_key_update(@info.name) unless key_of(updated, @primary) == key

            store(updated, replacing: key)
          end

          def delete(key)
            copy(@rows.delete(key))
          end

          private

          def store(tuple, replacing:)
            check_nils(tuple)
            check_unique(tuple, replacing)
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
              next unless @rows.any? { |row_key, row| row_key != replacing && key_of(row, index) == key }

              raise RecordNotUnique, "Duplicate key exists in unique index \"#{index.name}\" in space \"#{@info.name}\""
            end
          end

          def advance_sequence(tuple)
            return unless @sequence

            if tuple[@sequence].nil?
              tuple[@sequence] = @counter += 1
            else
              @counter = [@counter, tuple[@sequence]].max
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

          def copy(value)
            value && Marshal.load(Marshal.dump(value))
          end
        end
      end
    end
  end
end
