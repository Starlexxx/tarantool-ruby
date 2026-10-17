# frozen_string_literal: true

module Tarantool
  module OpenTelemetry
    # Span name and attributes of one client event. Only keys present in the payload become attributes, and the
    # payload never carries keys, tuples, arguments or credentials; the SQL text is added only when asked for.
    # @api private
    module Attributes
      REQUEST = 'request.tarantool'
      DB_KEYS = {
        request: 'db.operation', space: 'db.tarantool.space', index: 'db.tarantool.index',
        function: 'db.tarantool.function', statement_id: 'db.tarantool.statement_id',
        schema_reloaded: 'db.tarantool.schema_reloaded'
      }.freeze
      EVENT_KEYS = {
        reason: 'tarantool.reason', attempts: 'tarantool.attempts', read_only: 'tarantool.read_only',
        pending: 'tarantool.pending'
      }.freeze
      private_constant :REQUEST, :DB_KEYS, :EVENT_KEYS

      module_function

      def name(event, payload)
        return "tarantool.#{event.delete_suffix('.tarantool')}" unless event == REQUEST
        return 'tarantool' unless payload.key?(:request)

        ['tarantool', payload[:request], payload[:space] || payload[:function]].compact.join(' ').sub(' ', '.')
      end

      def for(event, payload, db_statement:)
        attributes = { 'db.system' => 'tarantool' }
        keys = event == REQUEST ? DB_KEYS : EVENT_KEYS
        keys.each { |key, attribute| attributes[attribute] = value(payload[key]) if payload.key?(key) }
        attributes['db.statement'] = payload[:sql] if db_statement == :include && payload.key?(:sql)

        attributes.merge(server(payload[:address]))
      end

      def value(value) = value.is_a?(Symbol) ? value.to_s : value

      # host:port or [ipv6]:port; anything without a port is a unix socket path.
      def server(address)
        return {} if address.nil?

        host, port = address.match(/\A\[?(.+?)\]?:(\d+)\z/)&.captures
        return { 'server.address' => address } unless port

        { 'server.address' => host, 'server.port' => port.to_i }
      end
    end
  end
end
