# frozen_string_literal: true

module Tarantool
  module Schema
    # Field type names. The server keeps a space format type verbatim (str stays str) but normalizes index part
    # types (str becomes string), so declarations accept only canonical names and live format types are mapped
    # onto them before comparing.
    module Types
      CANONICAL = %w[
        any unsigned string integer number double boolean decimal uuid datetime interval varbinary scalar array map
      ].freeze
      ALIASES = { 'str' => 'string', 'num' => 'number' }.freeze

      module_function

      def declared(type, context)
        name = type.to_s
        return -name if CANONICAL.include?(name)

        hint = canonical(name)
        raise ArgumentError, "#{context}: unknown type #{name.inspect}#{", use #{hint}" if hint}"
      end

      def live(type)
        name = type.to_s

        canonical(name) || name
      end

      def canonical(name)
        lower = name.downcase

        ALIASES.fetch(lower) { lower if CANONICAL.include?(lower) }
      end
    end
  end
end
