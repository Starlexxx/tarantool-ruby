# frozen_string_literal: true

# The dedicated pair of instances the :failover specs may stop and restart.
module FailoverHelpers
  module_function

  def uris = ENV.fetch('TARANTOOL_FAILOVER_URIS', '').split(',')
  def containers = ENV.fetch('TARANTOOL_FAILOVER_CONTAINERS', '').split(',')
end
