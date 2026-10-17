# frozen_string_literal: true

module Tarantool
  class Client
    # A Tarantool uuid value; only instances of this type are sent as MP_EXT uuid, never plain strings.
    UUID = Data.define(:value) do
      const_set(:FORMAT, /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

      def initialize(value:)
        raise ArgumentError, "invalid UUID: #{value.inspect}" unless value.is_a?(String) && value.match?(UUID::FORMAT)

        super(value: value.downcase.freeze)
      end

      def to_s
        value
      end
    end
  end
end
