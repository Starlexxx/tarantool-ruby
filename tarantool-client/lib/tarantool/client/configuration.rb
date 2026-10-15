# frozen_string_literal: true

require 'uri'

module Tarantool
  class Client
    # Immutable connection settings built from a URI and keyword options; options win.
    Configuration = Data.define(:host, :port, :path, :user, :password, :connect_timeout, :request_timeout) do
      def self.build(uri = nil, **options)
        new(**defaults, **parse_uri(uri), **options)
      end

      def self.defaults
        { host: 'localhost', port: 3301, path: nil, user: nil, password: nil, connect_timeout: 3, request_timeout: 10 }
      end

      def self.parse_uri(uri)
        return {} if uri.nil?

        match = %r{\Aunix/?:(?://)?(.+)\z}.match(uri)
        return { path: "/#{match[1].delete_prefix('/')}" } if match

        parse_tcp_uri(uri)
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
      private_class_method :defaults, :parse_uri, :parse_tcp_uri

      def address
        return path if path

        host.include?(':') ? "[#{host}]:#{port}" : "#{host}:#{port}"
      end

      def inspect
        fields = to_h.merge(password: password && '[FILTERED]').map { |k, v| "#{k}=#{v.inspect}" }.join(', ')
        "#<data #{self.class.name} #{fields}>"
      end
      alias_method :to_s, :inspect
    end
  end
end
