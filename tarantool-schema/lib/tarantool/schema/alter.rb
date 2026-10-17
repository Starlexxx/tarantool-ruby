# frozen_string_literal: true

module Tarantool
  module Schema
    # What plan and apply may change on a live space besides creating what is missing. Each entry is opted into
    # by name; nothing here ever drops or rewrites a field or an index.
    # @api private
    module Alter
      ALLOWED = %i[add_field].freeze

      def self.check(list)
        list = Array(list).map(&:to_sym)
        unknown = list - ALLOWED
        return list.freeze if unknown.empty?

        raise ArgumentError, "alter: unknown #{unknown.map(&:inspect).join(', ')}; allowed: #{ALLOWED.join(', ')}"
      end
    end
  end
end
