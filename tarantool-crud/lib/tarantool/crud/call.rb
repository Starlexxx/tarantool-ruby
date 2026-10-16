# frozen_string_literal: true

module Tarantool
  module Crud
    # One crud.<function> invocation: merges defaults, sets the transport timeout, unpacks errors.
    # @api private
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

      # For functions that take no options: the timeout, given or default, bounds only the transport.
      def without_options(function, arguments, timeout)
        timeout ||= @defaults.options_for(function)[:timeout]

        @caller.call("crud.#{function}", arguments, timeout: transport_timeout(timeout))
      end

      private

      def perform(function, arguments, options)
        options = @defaults.options_for(function).merge(options)

        @caller.call("crud.#{function}", [*arguments, options], timeout: transport_timeout(options[:timeout]))
      end

      def transport_timeout(timeout) = timeout && (timeout + @timeout_margin)
    end
  end
end
