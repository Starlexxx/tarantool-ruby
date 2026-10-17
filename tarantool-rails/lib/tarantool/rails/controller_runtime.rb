# frozen_string_literal: true

require 'active_support/core_ext/module/attr_internal'

module Tarantool
  module Rails
    # Adds the time spent in Tarantool requests to the "Completed" line of a controller action and takes it out
    # of the Views share, as ActiveRecord does with db_runtime.
    module ControllerRuntime
      extend ActiveSupport::Concern

      # @api private
      module ClassMethods
        def log_process_action(payload)
          messages = super
          runtime = payload[:tarantool_runtime]
          messages << format('Tarantool: %.1fms', runtime.to_f) if runtime

          messages
        end
      end

      private

      attr_internal :tarantool_runtime

      def process_action(...)
        LogSubscriber.reset_runtime

        super
      end

      def cleanup_view_runtime
        self.tarantool_runtime = tarantool_runtime.to_f + LogSubscriber.reset_runtime
        runtime = super
        during_render = LogSubscriber.reset_runtime
        self.tarantool_runtime += during_render

        runtime - during_render
      end

      def append_info_to_payload(payload)
        super
        payload[:tarantool_runtime] = tarantool_runtime.to_f + LogSubscriber.reset_runtime
      end
    end
  end
end
