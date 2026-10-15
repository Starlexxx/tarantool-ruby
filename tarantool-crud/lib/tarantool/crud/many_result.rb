# frozen_string_literal: true

module Tarantool
  module Crud
    # Result of a *_many call: the rows written plus the errors of the rows that failed.
    class ManyResult < Result
      attr_reader :errors

      def self.from_crud(response, errors = nil)
        super(response, errors: Array(errors).map { |error| Error.from(error) })
      end

      def initialize(errors:, **)
        super(**)
        @errors = errors
      end

      def success? = errors.empty?
    end
  end
end
