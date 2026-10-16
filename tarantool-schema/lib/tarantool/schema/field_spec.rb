# frozen_string_literal: true

module Tarantool
  module Schema
    # One entry of a space format with Tarantool's defaults filled in. Also used for live format entries.
    FieldSpec = Data.define(:name, :type, :is_nullable) do
      def self.build(raw)
        raise ArgumentError, "format entry must be a Hash, got #{raw.inspect}" unless raw.is_a?(Hash)

        context = "field #{raw[:name]}"
        Options.check(raw, %i[name type is_nullable], context)
        name = raw.fetch(:name) { raise ArgumentError, 'format entry without name' }

        new(name: name.to_sym, type: Types.declared(raw.fetch(:type, 'any'), context),
            is_nullable: Options.boolean(raw.fetch(:is_nullable, false), "#{context} is_nullable"))
      end

      def to_lua = { 'name' => name.to_s, 'type' => type, 'is_nullable' => is_nullable }
    end
  end
end
