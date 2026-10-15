# frozen_string_literal: true

module Tarantool
  module Crud
    # Entry point: crud functions over any caller responding to call(function, arguments, timeout:).
    class Client
      def initialize(caller, read: {}, write: {}, timeout_margin: 0.5)
        @caller = caller
        @call = Call.new(caller, defaults: Defaults.new(read:, write:), timeout_margin:)
      end

      def space(name) = Space.new(name, @call)

      def storage_info(**options) = @call.value('storage_info', [], options)

      # crud.stats takes no options and encodes an empty table as an Array.
      def stats(space = nil)
        stats = @caller.call('crud.stats', [space&.to_s].compact, timeout: nil).first
        stats.is_a?(Hash) ? stats : {}
      end
    end
  end
end
