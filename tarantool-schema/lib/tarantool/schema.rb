# frozen_string_literal: true

require 'tarantool/client'

require_relative 'schema/version'
require_relative 'schema/errors'
require_relative 'schema/options'
require_relative 'schema/alter'
require_relative 'schema/types'
require_relative 'schema/key_rules'
require_relative 'schema/field_spec'
require_relative 'schema/part_spec'
require_relative 'schema/index_spec'
require_relative 'schema/space_spec'
require_relative 'schema/space_rules'
require_relative 'schema/privileges'
require_relative 'schema/grant_spec'
require_relative 'schema/grant_inspector'
require_relative 'schema/grant_comparison'
require_relative 'schema/plan'
require_relative 'schema/definition'
require_relative 'schema/live_space'
require_relative 'schema/inspector'
require_relative 'schema/space_lister'
require_relative 'schema/live_definition'
require_relative 'schema/source'
require_relative 'schema/format_comparison'
require_relative 'schema/index_comparison'
require_relative 'schema/comparison'
require_relative 'schema/creation'

module Tarantool
  # Idempotent declaration of spaces, indexes, primary key sequences and grants, applied over an admin connection.
  module Schema
  end
end
