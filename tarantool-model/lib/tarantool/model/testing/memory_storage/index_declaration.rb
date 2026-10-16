# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # One index of a space declaration; the first index of a space is the primary one.
        # @api private
        class IndexDeclaration
          KEYS = %i[name parts unique type sequence].freeze
          PART_KEYS = %i[field type is_nullable path].freeze
          TYPES = %w[tree hash].freeze
          SEQUENCE_TYPES = %w[unsigned integer].freeze

          attr_reader :info, :sequence

          def initialize(entry, id:, fields:, owner:)
            Keys.check!(entry, KEYS, "#{owner} index")
            @owner = "#{owner} index #{Keys.fetch!(entry, :name, "#{owner} index")}"
            @fields = fields
            @info = Tarantool::Client::IndexInfo.new(
              id:, name: entry[:name].to_s, type: Keys.one_of!(entry.fetch(:type, 'tree'), TYPES, @owner),
              unique: entry.fetch(:unique, true), parts: parts(Keys.fetch!(entry, :parts, @owner))
            )
            check_unique!
            check_nullable!
            @sequence = sequence?(entry.fetch(:sequence, false))
          end

          private

          def parts(entries)
            raise ArgumentError, "#{@owner} has no parts" if entries.empty?

            entries.map { |entry| part(entry.is_a?(Hash) ? entry : { field: entry }) }
          end

          def part(entry)
            Keys.check!(entry, PART_KEYS, "#{@owner} part")
            raise ArgumentError, "#{@owner}: path parts are not supported" if entry[:path]

            name = Keys.fetch!(entry, :field, "#{@owner} part").to_s
            fieldno = @fields.index { |field| field.name == name }
            raise ArgumentError, "#{@owner} has no field #{name}" unless fieldno

            field = @fields[fieldno]
            type = Keys.one_of!(entry.fetch(:type, field.type), Declaration::TYPES, "#{@owner} part #{name}")

            Tarantool::Client::IndexInfo::Part.new(
              fieldno:, name:, type:, is_nullable: entry.fetch(:is_nullable, field.is_nullable), path: nil
            )
          end

          def check_unique!
            return if @info.unique

            raise ArgumentError, "#{@owner}: a primary index must be unique" if @info.id.zero?
            raise ArgumentError, "#{@owner}: a hash index must be unique" if @info.type == 'hash'
          end

          def check_nullable!
            return unless @info.parts.any?(&:is_nullable)

            raise ArgumentError, "#{@owner}: a primary index can not contain nullable parts" if @info.id.zero?
            raise ArgumentError, "#{@owner}: a hash index does not support nullable parts" if @info.type == 'hash'
          end

          def sequence?(requested)
            return false unless requested
            return true if @info.id.zero? && @info.parts.size == 1 && SEQUENCE_TYPES.include?(@info.parts.first.type)

            raise ArgumentError, "#{@owner}: a sequence needs a primary index with one unsigned or integer part"
          end
        end
      end
    end
  end
end
