# frozen_string_literal: true

module Tarantool
  module Model
    module Types
      # varbinary: msgpack sends an ASCII-8BIT String as bin and a UTF-8 one as str.
      class Binary < ActiveModel::Type::Value
        def type = :binary

        private

        def cast_value(value)
          value.is_a?(String) ? value.b : value
        end
      end
    end
  end
end
