# frozen_string_literal: true

module Tarantool
  module Schema
    # One part of an index key. Type and nullability left out stay nil until #inherit copies them from the
    # field, as Tarantool does (verified for JSON path parts too). A path points inside the field, so its type
    # cannot come from the field and must be declared.
    PartSpec = Data.define(:field, :type, :is_nullable, :path) do
      def self.build(raw)
        raw = { field: raw } unless raw.is_a?(Hash)
        context = "index part #{raw[:field]}"
        Options.check(raw, %i[field type is_nullable path], context)
        raise ArgumentError, "#{context}: a part with path needs a type" if raw[:path] && !raw[:type]

        new(**attributes(raw, context))
      end

      def self.attributes(raw, context)
        { field: raw.fetch(:field) { raise ArgumentError, 'index part without field' }.to_sym,
          type: raw[:type] && Types.declared(raw[:type], context),
          is_nullable: raw[:is_nullable].nil? ? nil : Options.boolean(raw[:is_nullable], "#{context} is_nullable"),
          path: raw[:path] && -raw[:path].to_s }
      end

      private_class_method :attributes

      def inherit(field)
        with(type: type || field.type, is_nullable: is_nullable.nil? ? field.is_nullable : is_nullable)
      end

      def to_lua = { 'field' => field.to_s, 'type' => type, 'is_nullable' => is_nullable, 'path' => path }.compact
    end
  end
end
