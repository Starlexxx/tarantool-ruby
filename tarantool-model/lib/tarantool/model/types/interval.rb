# frozen_string_literal: true

module Tarantool
  module Model
    module Types
      # MP_EXT interval; a Hash of units (e.g. from params) builds one.
      class Interval < ActiveModel::Type::Value
        def type = :interval

        private

        def cast_value(value)
          value.is_a?(Hash) ? Tarantool::Client::Interval.new(**value.transform_keys(&:to_sym)) : value
        end
      end
    end
  end
end
