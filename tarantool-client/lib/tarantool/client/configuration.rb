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
        return { path: uri.delete_prefix('unix:') } if uri.start_with?('unix:')

        parsed = URI.parse(uri.include?('://') ? uri : "tcp://#{uri}")
        {
          host: parsed.host,
          port: parsed.port,
          user: parsed.user && URI.decode_uri_component(parsed.user),
          password: parsed.password && URI.decode_uri_component(parsed.password)
        }.compact
      end
      private_class_method :defaults, :parse_uri

      def address
        path || "#{host}:#{port}"
      end
    end
  end
end
