# frozen_string_literal: true

module Tarantool
  module Model
    # Optimistic locking on the attribute named by locking_column, when the model declares it.
    module Locking
      extend ActiveSupport::Concern

      included do
        class_attribute :locking_column, instance_accessor: false, default: :lock_version
      end

      class_methods do
        def locking_enabled?
          !locking_column.nil? && attribute_names.include?(locking_column.to_s)
        end
      end

      private

      def create_row
        public_send("#{locking_column}=", 0) if locking_enabled? && public_send(locking_column).nil?

        super
      end

      def locking_column = self.class.locking_column

      def locking_enabled? = self.class.locking_enabled?
    end
  end
end
