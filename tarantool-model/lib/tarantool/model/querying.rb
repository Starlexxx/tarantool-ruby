# frozen_string_literal: true

module Tarantool
  module Model
    # Class-level reads; everything but find goes through a Relation.
    module Querying
      extend ActiveSupport::Concern

      class_methods do
        def all = Relation.new(self)

        def where(...) = all.where(...)

        def find_each(...) = all.find_each(...)

        def count = all.count

        def find_by(index:, key:) = where(index:, key:).first

        def find(key)
          key = Key.wrap(key)
          row = verified_storage.get(space_name, key)
          raise RecordNotFound.new(self, key) unless row

          instantiate(row)
        end
      end
    end
  end
end
