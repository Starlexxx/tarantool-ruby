# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/named_base'

module Tarantool
  module Generators
    # rails g tarantool:model User email:string age:unsigned?
    class ModelGenerator < ::Rails::Generators::NamedBase
      Field = Data.define(:name, :attribute_type, :field_type, :nullable) do
        def declaration
          "{ name: :#{name}, type: :#{field_type}#{', is_nullable: true' if nullable} }"
        end
      end

      TYPES = {
        'integer' => [':integer', 'integer'], 'unsigned' => [':integer', 'unsigned'], 'string' => [':string', 'string'],
        'boolean' => [':boolean', 'boolean'], 'decimal' => [':decimal', 'decimal'],
        'datetime' => [':datetime', 'datetime'], 'uuid' => ['Tarantool::Model::Types::UUID.new', 'uuid'],
        'interval' => ['Tarantool::Model::Types::Interval.new', 'interval'],
        'binary' => ['Tarantool::Model::Types::Binary.new', 'varbinary']
      }.freeze
      ID = Field.new(name: 'id', attribute_type: ':integer', field_type: 'unsigned', nullable: false)
      SCHEMA_PATH = 'config/tarantool_schema.rb'
      SCHEMA_END = /^end\s*\z/
      LINE_START = /^/

      source_root File.expand_path('templates', __dir__)

      argument :fields, type: :array, default: [], banner: 'name:type name:type?'
      class_option :skip_schema, type: :boolean, default: false, desc: "Do not add the space to #{SCHEMA_PATH}"

      # Runs before any file is written so an unknown type leaves nothing behind.
      def parse_fields
        model_fields
      end

      def create_model_file
        template 'model.rb.tt', File.join('app/models', class_path, "#{file_name}.rb")
      end

      def add_space_to_schema
        return if options[:skip_schema] || !File.exist?(File.join(destination_root, SCHEMA_PATH))

        inject_into_file SCHEMA_PATH, space_declaration, before: SCHEMA_END
      end

      private

      def model_fields
        @model_fields ||= begin
          declared = fields.map { |field| parse(field) }
          declared.any? { |field| field.name == 'id' } ? declared : [ID, *declared]
        end
      end

      def parse(field)
        name, type = field.split(':', 2)
        raise Thor::Error, "#{field}: expected name:type" if type.nil? || type.empty?

        nullable = type.end_with?('?')
        attribute_type, field_type = TYPES[type.delete_suffix('?')]
        raise Thor::Error, "unknown type #{type} for #{name}; use one of #{TYPES.keys.join(', ')}" unless attribute_type

        Field.new(name:, attribute_type:, field_type:, nullable:)
      end

      def space_declaration
        sequence = model_fields.first.equal?(ID) ? ', sequence: true' : ''
        lines = ["ensure_space :#{plural_table_name},", '             format: [',
                 model_fields.map { |field| "               #{field.declaration}" }.join(",\n"),
                 '             ],', '             indexes: [',
                 "               { name: :primary, parts: [:#{model_fields.first.name}]#{sequence} }", '             ]']

        "\n#{lines.join("\n").gsub(LINE_START, '  ')}\n"
      end
    end
  end
end
