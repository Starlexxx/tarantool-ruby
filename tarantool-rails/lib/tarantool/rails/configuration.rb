# frozen_string_literal: true

module Tarantool
  module Rails
    # One environment section of config/tarantool.yml, validated and split by consumer: addresses and client
    # options go to the Pool, read/write to Storage::Box, crud to the crud client, admin_uri to the rake tasks.
    Configuration = Data.define(:addresses, :client_options, :storage, :read, :write, :crud, :admin_uri) do
      def inspect
        fields = to_h.map { |key, value| "#{key}=#{filtered(key, value).inspect}" }.join(', ')

        "#<data #{self.class.name} #{fields}>"
      end
      alias_method :to_s, :inspect

      private

      def filtered(key, value)
        case key
        when :client_options then value.key?(:password) ? value.merge(password: '[FILTERED]') : value
        when :admin_uri then value&.sub(Configuration::URI_PASSWORD, ':[FILTERED]@')
        else value
        end
      end
    end

    # Builds a Configuration from the Hash config_for returns.
    class Configuration
      CLIENT_KEYS = %i[user password connect_timeout request_timeout reconnect reconnect_attempts reconnect_delay
                       reconnect_max_delay max_frame_size].freeze
      KEYS = (CLIENT_KEYS + %i[addresses address read write storage crud admin_uri]).freeze
      CRUD_KEYS = %i[primary_index read write timeout_margin].freeze
      STORAGES = %i[box crud].freeze
      URI_PASSWORD = %r{:[^:@/]*@}

      class << self
        def from_hash(hash)
          hash = checked(hash.to_h.transform_keys(&:to_sym))

          new(addresses: addresses(hash), client_options: hash.slice(*CLIENT_KEYS), storage: storage(hash[:storage]),
              read: options(hash[:read]), write: options(hash[:write]), crud: crud(hash[:crud]),
              admin_uri: hash[:admin_uri])
        end

        private

        def checked(hash)
          unknown = hash.keys - KEYS
          raise ArgumentError, "unknown key #{unknown.first} in config/tarantool.yml" if unknown.any?

          hash
        end

        def addresses(hash)
          addresses = Array(hash[:addresses] || hash[:address])
          raise ArgumentError, 'addresses is required in config/tarantool.yml' if addresses.empty?

          addresses
        end

        def storage(value)
          storage = (value || :box).to_sym
          raise ArgumentError, "storage must be box or crud, got #{value.inspect}" unless STORAGES.include?(storage)

          storage
        end

        def options(hash)
          options = (hash || {}).to_h.transform_keys(&:to_sym)
          options[:mode] = options[:mode].to_sym if options.key?(:mode)

          options
        end

        def crud(hash)
          crud = { primary_index: :primary }.merge((hash || {}).to_h.transform_keys(&:to_sym))
          unknown = crud.keys - CRUD_KEYS
          raise ArgumentError, "unknown key #{unknown.first} in crud" if unknown.any?

          crud.merge(primary_index: crud[:primary_index].to_sym)
        end
      end
    end
  end
end
