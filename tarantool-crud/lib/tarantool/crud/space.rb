# frozen_string_literal: true

module Tarantool
  module Crud
    # Operations on one sharded space; Hash rows go to the *_object crud variants.
    class Space
      attr_reader :name

      def initialize(name, call)
        @name = name.to_s
        @call = call
      end

      def insert(tuple, **) = row(variant('insert', tuple), tuple, **)

      def replace(tuple, **) = row(variant('replace', tuple), tuple, **)

      def upsert(tuple, operations, **) = row(variant('upsert', tuple), tuple, operations, **)

      def get(key, **) = row('get', key, **)

      def update(key, operations, **) = row('update', key, operations, **)

      def delete(key, **) = row('delete', key, **)

      private

      def value(function, *arguments, **options) = @call.value(function, [name, *arguments], options)

      def row(...) = Result.from_crud(value(...)).first

      def variant(function, tuple) = tuple.is_a?(Hash) ? "#{function}_object" : function
    end
  end
end
