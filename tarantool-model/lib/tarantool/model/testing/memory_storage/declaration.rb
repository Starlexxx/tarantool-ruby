# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # One space in tarantool-schema's ensure_space shape, checked and turned into the SpaceInfo that
        # Storage::Box::Layout reads. Types are checked here but values are not type-checked.
        # @api private
        class Declaration
          SPACE_KEYS = %i[engine format indexes].freeze
          FIELD_KEYS = %i[name type is_nullable].freeze
          TYPES = %w[unsigned string integer number double boolean decimal uuid datetime interval varbinary scalar
                     array map any].freeze

          attr_reader :space_info, :sequence

          def initialize(name, schema)
            owner = "space #{name}"
            Keys.check!(schema, SPACE_KEYS, owner)
            fields = Keys.fetch!(schema, :format, owner).map { |entry| field(entry, owner) }
            indexes = index_declarations(Keys.fetch!(schema, :indexes, owner), fields, owner)
            @space_info = Tarantool::Client::SpaceInfo.new(
              id: 0, name: name.to_s, fields:, indexes: indexes.to_h { |index| [index.info.name, index.info] }
            )
            @sequence = indexes.first.sequence
          end

          private

          def field(entry, owner)
            Keys.check!(entry, FIELD_KEYS, "#{owner} field")
            name = Keys.fetch!(entry, :name, "#{owner} field").to_s
            type = Keys.one_of!(entry.fetch(:type, 'any'), TYPES, "#{owner} field #{name}")

            Tarantool::Client::SpaceInfo::Field.new(name:, type:, is_nullable: entry.fetch(:is_nullable, false))
          end

          def index_declarations(entries, fields, owner)
            Keys.distinct!(fields.map(&:name), owner)
            raise ArgumentError, "#{owner} has no indexes" if entries.empty?

            entries.each_with_index.map { |entry, id| IndexDeclaration.new(entry, id:, fields:, owner:) }
                   .tap { |indexes| Keys.distinct!(indexes.map { |index| index.info.name }, owner) }
          end
        end
      end
    end
  end
end
