# frozen_string_literal: true

module Tarantool
  class Client
    class Instrumentation
      # Log level and line of each event the client emits.
      # @api private
      module LogLines
        LEVELS = {
          'request.tarantool' => :debug, 'disconnect.tarantool' => :warn, 'reconnect.tarantool' => :info,
          'reconnect_failed.tarantool' => :error, 'fork.tarantool' => :info, 'role_change.tarantool' => :info
        }.freeze

        LINES = {
          'request.tarantool' => ->(payload, duration) { request(payload, duration) },
          'disconnect.tarantool' => lambda do |payload, _duration|
            "tarantool disconnected from #{payload[:address]}: #{payload[:reason]}"
          end,
          'reconnect.tarantool' => lambda do |payload, _duration|
            "tarantool reconnected to #{payload[:address]} after #{attempts(payload[:attempts])}"
          end,
          'reconnect_failed.tarantool' => lambda do |payload, _duration|
            "tarantool gave up reconnecting to #{payload[:address]}: #{error(payload)}"
          end,
          'fork.tarantool' => lambda do |payload, _duration|
            "tarantool reopened connection to #{payload[:address]} after fork"
          end,
          'role_change.tarantool' => lambda do |payload, _duration|
            "tarantool #{payload[:address]} is now #{payload[:read_only] ? 'read-only' : 'writable'}"
          end
        }.freeze

        module_function

        def level(name) = LEVELS[name]

        def line(name, payload, duration) = LINES[name]&.call(payload, duration)

        def request(payload, duration)
          parts = [request_name(payload)]
          %i[space index function].each { |key| parts << "#{key}=#{payload[key]}" if payload.key?(key) }
          parts << format('%.2fms', duration * 1000) << payload[:address]
          parts << "error=#{request_error(payload)}" if payload.key?(:exception)
          parts << 'schema_reloaded' if payload[:schema_reloaded]

          parts.join(' ')
        end

        def request_name(payload) = payload[:request] ? "tarantool #{payload[:request]}" : 'tarantool'

        def attempts(count) = count == 1 ? '1 attempt' : "#{count} attempts"
        def error(payload) = payload[:exception].join(': ')

        # The message may quote data (ER_TUPLE_FOUND repeats the tuple), so the request line keeps only the
        # class and, when the exception has one, its code.
        def request_error(payload)
          exception = payload[:exception_object]
          klass = exception ? exception.class.name : payload[:exception].first
          code = exception.respond_to?(:code) ? exception.code : nil

          code ? "#{klass}(#{code})" : klass
        end
      end
    end
  end
end
