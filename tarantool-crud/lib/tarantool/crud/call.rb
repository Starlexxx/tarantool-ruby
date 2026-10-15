# frozen_string_literal: true

module Tarantool
  module Crud
    # One crud.<function> invocation: merges defaults, sets the transport timeout, unpacks errors.
    class Call
      def initialize(caller, defaults:, timeout_margin:)
        @caller = caller
        @defaults = defaults
        @timeout_margin = timeout_margin
      end

      def value(function, arguments, options)
        result, error = perform(function, arguments, options)
        raise Error.from(error) if error

        result
      end

      def many(function, arguments, options) = ManyResult.from_crud(*perform(function, arguments, options))

      private

      def perform(function, arguments, options)
        options = @defaults.options_for(function).merge(options)
        timeout = options[:timeout] && (options[:timeout] + @timeout_margin)
        @caller.call("crud.#{function}", [*arguments, options], timeout:)
      end
    end
  end
end
