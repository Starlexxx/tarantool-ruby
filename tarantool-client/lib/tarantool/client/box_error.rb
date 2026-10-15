# frozen_string_literal: true

module Tarantool
  class Client
    # A box.error object returned as data (MP_ERROR extension), with its cause chain.
    BoxError = Data.define(:type, :message, :code, :file, :line, :errno, :fields, :cause) do
      def self.from_stack(entries)
        entries.reverse_each.reduce(nil) do |cause, entry|
          attributes = entry.transform_keys(Protocol::Constants::ERROR_FIELDS)
          new(**Protocol::Constants::ERROR_FIELDS.values.to_h { |field| [field, attributes[field]] }, cause:)
        end
      end
    end
  end
end
