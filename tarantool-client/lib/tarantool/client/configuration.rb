# frozen_string_literal: true

require 'uri'

module Tarantool
  class Client
    # Immutable connection settings built from a URI and keyword options; options win.
    Configuration = Data.define(
      :host, :port, :path, :user, :password, :connect_timeout, :request_timeout,
      :reconnect, :reconnect_attempts, :reconnect_delay, :reconnect_max_delay,
      :max_frame_size, :instrumenter, :logger
    ) do
      const_set(:UNIX_URI, %r{\Aunix/?:})
      const_set(:UNIX_PATH, %r{\Aunix/?:(?://(?=/))?(.+)\z})
      const_set(:EMPTY_PATH, %r{\A/*\z})

      def self.build(uri = nil, **options)
        new(**defaults, **parse_uri(uri), **options)
      end

      def self.defaults
        {
          host: 'localhost', port: 3301, path: nil, user: nil, password: nil, connect_timeout: 3, request_timeout: 10,
          reconnect: true, reconnect_attempts: Float::INFINITY, reconnect_delay: 0.1, reconnect_max_delay: 5,
          max_frame_size: 64 * 1024 * 1024, instrumenter: nil, logger: nil
        }
      end

      def self.parse_uri(uri)
        return {} if uri.nil?
        return parse_unix_uri(uri) if uri.match?(Configuration::UNIX_URI)

        parse_tcp_uri(uri)
      end

      def self.parse_unix_uri(uri)
        match = Configuration::UNIX_PATH.match(uri)
        path = match && match[1]
        raise ArgumentError, 'invalid Tarantool URI' if path.nil? || path.match?(Configuration::EMPTY_PATH)

        { path: path }
      end

      def self.parse_tcp_uri(uri)
        parsed = URI.parse(uri.include?('://') ? uri : "tcp://#{uri}")
        user = parsed.user == '' ? nil : parsed.user

        {
          host: parsed.hostname,
          port: parsed.port,
          user: user && URI.decode_uri_component(user),
          password: parsed.password && URI.decode_uri_component(parsed.password)
        }.compact
      rescue URI::InvalidURIError
        raise ArgumentError, 'invalid Tarantool URI'
      end
      private_class_method :defaults, :parse_uri, :parse_unix_uri, :parse_tcp_uri

      def address
        return path if path

        host.include?(':') ? "[#{host}]:#{port}" : "#{host}:#{port}"
      end

      def inspect
        fields = to_h.map { |key, value| "#{key}=#{inspect_field(key, value)}" }.join(', ')

        "#<data #{self.class.name} #{fields}>"
      end
      alias_method :to_s, :inspect

      def pretty_print(printer) = printer.text(inspect)

      private

      def inspect_field(key, value)
        case key
        when :password then (value && '[FILTERED]').inspect
        when :instrumenter, :logger then inspect_object(value)
        else value.inspect
        end
      end

      def inspect_object(value)
        return 'nil' unless value

        klass = value.is_a?(Module) ? value : value.class
        klass.name ? "#<#{klass.name}>" : klass.inspect
      end
    end
  end
end
