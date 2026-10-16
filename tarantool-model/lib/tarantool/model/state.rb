# frozen_string_literal: true

module Tarantool
  module Model
    # Persistence state and the raw tuple a record was loaded from or last written with; Relation#after
    # continues past that tuple.
    module State
      extend ActiveSupport::Concern

      class_methods do
        # @api private
        def instantiate(row)
          new.tap { |record| record.send(:init_with_row, row) }
        end
      end

      attr_reader :tuple

      def new_record? = !@persisted

      def persisted? = @persisted == true && !destroyed?

      def destroyed? = @destroyed == true

      # Assigning to a destroyed record must fail; freezing self alone leaves the attribute set writable.
      def freeze
        @attributes = @attributes.clone.freeze

        super
      end

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

      def written(row)
        assign_row(row)

        changes_applied
      end

      def key_in_database
        self.class.primary_key_names.map { |name| attribute_was(name.to_s) }
      end

      def space_storage = self.class.verified_storage

      def writing_storage = self.class.writing_storage

      def space_name = self.class.space_name
    end
  end
end
