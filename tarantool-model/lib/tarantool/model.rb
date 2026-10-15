# frozen_string_literal: true

require 'active_model'
require 'tarantool/client'

require_relative 'model/version'
require_relative 'model/errors'
require_relative 'model/row'
require_relative 'model/key'
require_relative 'model/types/uuid'
require_relative 'model/types/interval'
require_relative 'model/types/binary'
require_relative 'model/settings'
require_relative 'model/state'
require_relative 'model/storage/box/layout'
require_relative 'model/storage/box'

module Tarantool
  # ActiveModel-based model over a Tarantool space. Attribute names are the space format field names.
  module Model
    extend ActiveSupport::Concern

    include ActiveModel::API
    include ActiveModel::Attributes
    include ActiveModel::Dirty
    include ActiveModel::Validations::Callbacks
    include ActiveModel::Serializers::JSON
    include Settings
    include State
  end
end
