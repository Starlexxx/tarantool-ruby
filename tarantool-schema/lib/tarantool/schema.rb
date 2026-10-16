# frozen_string_literal: true

require 'tarantool/client'

require_relative 'schema/version'
require_relative 'schema/errors'
require_relative 'schema/options'
require_relative 'schema/types'
require_relative 'schema/field_spec'
require_relative 'schema/part_spec'
require_relative 'schema/index_spec'
require_relative 'schema/space_spec'
require_relative 'schema/space_rules'
require_relative 'schema/definition'
require_relative 'schema/live_space'
require_relative 'schema/inspector'
require_relative 'schema/format_comparison'
require_relative 'schema/index_comparison'

module Tarantool
  # Idempotent declaration of spaces, indexes and primary key sequences, applied over an admin connection.
  module Schema
  end
end
