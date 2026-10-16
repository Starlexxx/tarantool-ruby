# frozen_string_literal: true

module Tarantool
  module Model
    # Storage, space name and primary key of a model class, inherited by subclasses.
    module Settings
      extend ActiveSupport::Concern

      included do
        class_attribute :storage, instance_accessor: false
        class_attribute :primary_key, instance_accessor: false, default: :id
        class_attribute :_space_name, instance_accessor: false
      end

      class_methods do
        def space_name
          _space_name || model_name.plural
        end

        def space_name=(name)
          self._space_name = name
        end

        def primary_key_names
          Array(primary_key)
        end

        # The schema check runs once per class and storage, before the first operation.
        def verified_storage
          current = storage
          raise Error, "#{name}.storage is not set" unless current
          return current if @verified_storage.equal?(current)

          current.verify(space_name, attributes: attribute_names.map(&:to_sym), primary_key: primary_key_names)

          @verified_storage = current
        end

        def writing_storage
          verified_storage.tap { |s| Transactions.check_write!(s) }
        end
      end

      def to_key
        self.class.primary_key_names.map { |name| public_send(name) } if persisted?
      end
    end
  end
end
