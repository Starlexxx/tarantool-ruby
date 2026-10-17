# frozen_string_literal: true

require 'active_model'
require 'tarantool/client'

require_relative 'model/version'
require_relative 'model/errors'
require_relative 'model/row'
require_relative 'model/key'
require_relative 'model/transactions'
require_relative 'model/transactional'
require_relative 'model/types/uuid'
require_relative 'model/types/interval'
require_relative 'model/types/binary'
require_relative 'model/settings'
require_relative 'model/state'
require_relative 'model/persistence'
require_relative 'model/counters'
require_relative 'model/relation'
require_relative 'model/querying'
require_relative 'model/storage/box/layout'
require_relative 'model/storage/box'
require_relative 'model/storage/crud'

module Tarantool
  # ActiveModel-based model over a Tarantool space. Attribute names are the space format field names.
  module Model
    extend ActiveSupport::Concern

    DEFAULT_STORAGE_LOCK = Mutex.new
    private_constant :DEFAULT_STORAGE_LOCK

    class << self
      # Storage for models that set none of their own: a storage, or a Proc called once on first use.
      attr_writer :default_storage

      def default_storage
        DEFAULT_STORAGE_LOCK.synchronize do
          @default_storage = @default_storage.call if @default_storage.is_a?(Proc)

          @default_storage
        end
      end
    end

    include ActiveModel::API
    include ActiveModel::Attributes
    include ActiveModel::Dirty
    include ActiveModel::Validations::Callbacks
    include ActiveModel::Serializers::JSON
    include Settings
    include State
    include Persistence
    include Counters
    include Transactional
    include Querying
  end
end
