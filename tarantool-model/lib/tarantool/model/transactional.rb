# frozen_string_literal: true

module Tarantool
  module Model
    # Model.transaction delegates to the storage; every model sharing that storage instance writes through the
    # open transaction. In-memory record state is not reverted on rollback.
    module Transactional
      extend ActiveSupport::Concern

      class_methods do
        def transaction(**, &)
          verified_storage.transaction(**, &)
        end
      end
    end
  end
end
