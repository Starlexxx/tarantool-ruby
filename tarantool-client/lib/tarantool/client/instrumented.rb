# frozen_string_literal: true

module Tarantool
  class Client
    # Request events around the requests of Client and Stream. Includers implement
    # transmit(request, timeout:, schema_version:, on_push:) and
    # transmit_on_space(space, index, timeout:, format:, payload:, &), and set @instrumentation,
    # nil when nothing is configured.
    # @api private
    module Instrumented
      private

      def perform(request, timeout: nil, schema_version: nil, on_push: nil)
        instrumented(request) { transmit(request, timeout:, schema_version:, on_push:) }
      end

      def perform_on_space(space, index, timeout: nil, format: false, &)
        return transmit_on_space(space, index, timeout:, format:, &) unless @instrumentation

        perform_on_space_instrumented(space, index, timeout, format, &)
      end

      def instrumented(request, &)
        return yield unless @instrumentation

        @instrumentation.request(Instrumentation::RequestPayload.build(request), &)
      end

      # The request is built only once names resolve to ids, so its type and index join the payload then.
      def perform_on_space_instrumented(space, index, timeout, format, &)
        payload = { space: }
        @instrumentation.request(payload) do
          transmit_on_space(space, index, timeout:, format:, payload:) do |*resolved|
            yield(*resolved).tap { |request| Instrumentation::RequestPayload.describe(payload, request, index) }
          end
        end
      end

      def mark_schema_reloaded(payload) = payload&.store(:schema_reloaded, true)
    end
  end
end
