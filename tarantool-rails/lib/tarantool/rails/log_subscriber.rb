# frozen_string_literal: true

module Tarantool
  module Rails
    # ActiveRecord-style lines for the client's events, and the time spent in requests per thread so the
    # controller log can show a Tarantool share next to Views.
    class LogSubscriber < ActiveSupport::LogSubscriber
      COLORS = {
        select: MAGENTA, insert: GREEN, replace: GREEN, upsert: GREEN, update: YELLOW, delete: RED,
        begin: CYAN, commit: CYAN, rollback: CYAN
      }.freeze
      PRIMARY = [0, 'primary', :primary].freeze
      RUNTIME = :tarantool_rails_runtime
      private_constant :COLORS, :PRIMARY, :RUNTIME

      class << self
        def runtime
          ActiveSupport::IsolatedExecutionState[RUNTIME] ||= 0.0
        end

        def runtime=(value)
          ActiveSupport::IsolatedExecutionState[RUNTIME] = value
        end

        def reset_runtime
          runtime.tap { self.runtime = 0.0 }
        end
      end

      def request(event)
        self.class.runtime += event.duration
        return unless logger.debug?

        payload = event.payload
        name = color(request_name(payload), COLORS.fetch(payload[:request], WHITE), bold: true)

        debug [name, format('(%.2fms)', event.duration), *request_details(payload)].join(' ')
      end

      def disconnect(event)
        warn "Tarantool disconnected from #{event.payload[:address]}: #{event.payload[:reason]}"
      end

      def reconnect(event)
        info "Tarantool reconnected to #{event.payload[:address]} after #{attempts(event.payload[:attempts])}"
      end

      def reconnect_failed(event)
        error "Tarantool gave up reconnecting to #{event.payload[:address]}: #{event.payload[:exception].join(': ')}"
      end

      def fork(event)
        info "Tarantool reopened #{event.payload[:address]} after fork"
      end

      def role_change(event)
        info "Tarantool #{event.payload[:address]} is now #{event.payload[:read_only] ? 'read-only' : 'writable'}"
      end

      private

      def request_name(payload)
        parts = ['Tarantool', payload[:request], payload[:space], payload[:function]]
        parts << "by #{payload[:index]}" if payload.key?(:index) && !PRIMARY.include?(payload[:index])
        parts << "##{payload[:statement_id]}" if payload.key?(:statement_id)

        parts.compact.join(' ')
      end

      def request_details(payload)
        details = [payload[:sql], payload[:address]]
        details << request_error(payload) if payload.key?(:exception)
        details << 'schema_reloaded' if payload[:schema_reloaded]

        details.compact
      end

      # The message may quote data (a duplicate key repeats the tuple); the line keeps the class and code.
      def request_error(payload)
        exception = payload[:exception_object]
        klass = exception ? exception.class.name : payload[:exception].first
        code = exception.respond_to?(:code) ? exception.code : nil

        code ? "#{klass}(#{code})" : klass
      end

      def attempts(count)
        count == 1 ? '1 attempt' : "#{count} attempts"
      end
    end
  end
end
