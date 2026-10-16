# frozen_string_literal: true

require 'tarantool/client'

require_relative 'schema/version'
require_relative 'schema/errors'

module Tarantool
  # Idempotent declaration of spaces, indexes and primary key sequences, applied over an admin connection.
  module Schema
  end
end
