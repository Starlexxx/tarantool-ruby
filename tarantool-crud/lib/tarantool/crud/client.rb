# frozen_string_literal: true

module Tarantool
  module Crud
    # Entry point: crud functions over any caller responding to call(function, arguments, timeout:).
    class Client
      def initialize(caller, read: {}, write: {}, timeout_margin: 0.5)
        @call = Call.new(caller, defaults: Defaults.new(read:, write:), timeout_margin:)
      end

      def space(name) = Space.new(name, @call)

      def storage_info(**options) = @call.value('storage_info', [], options)

      # The format and indexes of one space, or of every space keyed by name, as crud sees them through the
      # router: the same shape as a tarantool-schema declaration, so MemoryStorage.new(crud.schema, behaves_like: :crud)
      # works. An unknown space raises SchemaError.
      def schema(space = nil, **options)
        raw = @call.value('schema', [space&.to_s], options)

        space ? Schema.space(raw) : Schema.all(raw)
      end

      # crud.stats takes no options and encodes an empty table as an Array.
      def stats(space = nil, timeout: nil)
        stats = @call.without_options('stats', [space&.to_s].compact, timeout).first

        stats.is_a?(Hash) ? stats : {}
      end
    end
  end
end
