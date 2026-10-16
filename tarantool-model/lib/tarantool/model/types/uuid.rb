# frozen_string_literal: true

module Tarantool
  module Model
    module Types
      # MP_EXT uuid. A malformed String casts to nil, as Rails' uuid types do.
      class UUID < ActiveModel::Type::Value
        def type = :uuid

        private

        def cast_value(value)
          return value if value.is_a?(Tarantool::Client::UUID)
          return unless value.is_a?(String) && value.match?(Tarantool::Client::UUID::FORMAT)

          Tarantool::Client::UUID.new(value:)
        end
      end
    end
  end
end
