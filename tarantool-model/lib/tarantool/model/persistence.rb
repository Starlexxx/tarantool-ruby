# frozen_string_literal: true

module Tarantool
  module Model
    # create, save, update, destroy and reload with validations and callbacks. Every write refreshes the
    # attributes from the row the storage returns, so server-side defaults and sequences show up.
    module Persistence
      extend ActiveSupport::Concern

      included do
        extend ActiveModel::Callbacks

        define_model_callbacks :save, :create, :update, :destroy
      end

      class_methods do
        def create(attributes = {})
          new(attributes).tap(&:save)
        end

        def create!(attributes = {})
          new(attributes).tap(&:save!)
        end
      end

      def save
        valid? && persist
      end

      def save!
        raise RecordInvalid, self unless valid?

        persist || raise(RecordNotSaved, self)
      end

      def update(attributes)
        assign_attributes(attributes)

        save
      end

      def update!(attributes)
        assign_attributes(attributes)

        save!
      end

      # A row that is already gone still counts as destroyed.
      def destroy
        return false unless run_callbacks(:destroy) { delete_row }

        freeze
      end

      def reload
        row = space_storage.get(space_name, key_in_database)
        raise RecordNotFound.new(self.class, key_in_database) unless row

        assign_row(row)
        clear_changes_information

        self
      end

      private

      def persist
        run_callbacks(:save) { new_record? ? create_row : update_row }
      end

      def create_row
        run_callbacks(:create) do
          written(writing_storage.insert(space_name, attributes.transform_keys(&:to_sym)))

          @persisted = true
        end
      end

      def update_row
        raise ArgumentError, "the primary key of a persisted #{self.class.name} cannot change" if primary_key_changed?

        run_callbacks(:update) do
          written(updated_row) if update_pending?

          true
        end
      end

      def update_pending? = changed?

      def updated_row
        write_row(update_operations)
      end

      def update_operations
        changes.map { |name, (_was, value)| ['=', name, value] }
      end

      def write_row(operations)
        writing_storage.update(space_name, key_in_database, operations) ||
          raise(RecordNotFound.new(self.class, key_in_database))
      end

      def delete_row
        writing_storage.delete(space_name, key_in_database) if persisted?

        @destroyed = true
      end

      def primary_key_changed?
        self.class.primary_key_names.any? { |name| attribute_changed?(name.to_s) }
      end
    end
  end
end
