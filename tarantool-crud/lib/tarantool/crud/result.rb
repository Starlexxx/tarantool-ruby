# frozen_string_literal: true

module Tarantool
  module Crud
    # Rows returned by a crud function, as Hashes keyed by field name.
    class Result
      include Enumerable

      attr_reader :metadata, :tuples

      def self.from_crud(response, **)
        response ||= {}
        new(metadata: response.fetch('metadata', []).map { |field| field.transform_keys(&:to_sym) },
            tuples: response.fetch('rows', []), **)
      end

      def initialize(metadata:, tuples:)
        @metadata = metadata
        @tuples = tuples
        names = metadata.map { |field| field[:name].to_sym }
        @rows = tuples.map { |tuple| names.zip(tuple).to_h }
      end

      def each(&) = @rows.each(&)

      def last = @rows.last

      def size = @rows.size

      def empty? = @rows.empty?
    end
  end
end
