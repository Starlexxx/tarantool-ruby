# frozen_string_literal: true

module Tarantool
  module Schema
    # Privileges a grant on a space may name, with their bits in _priv. execute is left out: 3.x rejects it on
    # a space. Names are kept in bit order, the order box.schema.user.info prints them in.
    # @api private
    module Privileges
      BITS = { 'read' => 1, 'write' => 2, 'usage' => 16, 'create' => 32, 'drop' => 64, 'alter' => 128,
               'trigger' => 512, 'insert' => 1024, 'update' => 2048, 'delete' => 4096 }.freeze

      module_function

      def check(list, context)
        names = Array(list).map(&:to_s)
        raise ArgumentError, "#{context}: no privileges" if names.empty?

        unknown = names.reject { |name| BITS.key?(name) }
        if unknown.any?
          raise ArgumentError, "#{context}: unknown privilege #{describe(unknown)}; allowed: #{BITS.keys.join(', ')}"
        end

        BITS.keys & names
      end

      def describe(names) = names.map { |name| name.to_sym.inspect }.join(', ')

      def names(mask) = BITS.select { |_, bit| mask.anybits?(bit) }.keys
    end
  end
end
