# frozen_string_literal: true

module Tarantool
  module Model
    # Atomic '+'/'-' on the server, without validations or callbacks. Only the counter is taken from the
    # response, so other unsaved changes of the record survive.
    module Counters
      def increment!(attribute, by = 1)
        change_counter('+', attribute, by)
      end

      def decrement!(attribute, by = 1)
        change_counter('-', attribute, by)
      end

      private

      def change_counter(operator, attribute, by)
        row = writing_storage.update(space_name, key_in_database, [[operator, attribute.to_s, by]])
        raise RecordNotFound.new(self.class, key_in_database) unless row

        @tuple = row.tuple
        public_send("#{attribute}=", row.attributes.fetch(attribute.to_sym))
        clear_attribute_changes([attribute])

        self
      end
    end
  end
end
