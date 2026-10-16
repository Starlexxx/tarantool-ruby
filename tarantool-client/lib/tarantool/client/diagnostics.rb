# frozen_string_literal: true

module Tarantool
  class Client
    # Warnings from background threads: to the configured logger, else to stderr.
    # @api private
    module Diagnostics
      module_function

      # Called from rescue blocks of background threads, which must outlive a broken logger.
      def warn(logger, message)
        return Kernel.warn(message) unless logger

        logger.warn(message)
      rescue StandardError
        Kernel.warn(message)
      end
    end
  end
end
