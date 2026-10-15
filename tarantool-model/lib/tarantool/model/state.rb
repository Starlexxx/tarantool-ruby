# frozen_string_literal: true

module Tarantool
  module Model
    # Persistence state and the raw tuple a record was loaded from or last written with; Relation#after
    # continues past that tuple.
    module State
      extend ActiveSupport::Concern

      class_methods do
        def instantiate(row)
          new.tap { |record| record.send(:init_with_row, row) }
        end
      end

      attr_reader :tuple

      def new_record? = !@persisted

      def persisted? = @persisted == true && !destroyed?

      def destroyed? = @destroyed == true

      private

      def init_with_row(row)
        assign_row(row)
        clear_changes_information

        @persisted = true
      end

      def assign_row(row)
        @tuple = row.tuple

        assign_attributes(row.attributes.slice(*self.class.attribute_names.map(&:to_sym)))
      end
    end
  end
end
