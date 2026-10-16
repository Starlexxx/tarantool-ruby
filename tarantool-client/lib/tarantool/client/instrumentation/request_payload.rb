# frozen_string_literal: true

module Tarantool
  class Client
    class Instrumentation
      # Request event fields taken from a request. Keys, tuples, arguments and bindings stay out: they may hold
      # personal data.
      # @api private
      module RequestPayload
        NAMES = {
          Protocol::Requests::Ping => :ping, Protocol::Requests::Select => :select,
          Protocol::Requests::Insert => :insert, Protocol::Requests::Replace => :replace,
          Protocol::Requests::Update => :update, Protocol::Requests::Upsert => :upsert,
          Protocol::Requests::Delete => :delete, Protocol::Requests::Call => :call,
          Protocol::Requests::Eval => :eval, Protocol::Requests::Execute => :execute,
          Protocol::Requests::Prepare => :prepare, Protocol::Requests::Begin => :begin,
          Protocol::Requests::Commit => :commit, Protocol::Requests::Rollback => :rollback
        }.freeze

        module_function

        def build(request) = describe({}, request)

        # Space operations put space and index in first; only requests that have an index keep it.
        def describe(payload, request)
          payload[:request] = NAMES.fetch(request.class)
          payload.delete(:index) unless request.respond_to?(:index_id)
          case request
          when Protocol::Requests::Call then payload[:function] = request.function_name
          when Protocol::Requests::Execute, Protocol::Requests::Prepare then add_statement(payload, request.statement)
          end

          payload
        end

        def add_statement(payload, statement)
          payload[statement.is_a?(Integer) ? :statement_id : :sql] = statement
        end
      end
    end
  end
end
