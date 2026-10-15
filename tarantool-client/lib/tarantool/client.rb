# frozen_string_literal: true

require 'msgpack'

require_relative 'client/version'
require_relative 'client/errors'
require_relative 'client/configuration'
require_relative 'client/protocol/constants'
require_relative 'client/box_error'
require_relative 'client/protocol/response'
require_relative 'client/protocol/codec'
require_relative 'client/protocol/greeting'
require_relative 'client/protocol/auth/chap_sha1'
require_relative 'client/protocol/requests/ping'
require_relative 'client/protocol/requests/select'
require_relative 'client/protocol/requests/insert'
require_relative 'client/protocol/requests/replace'
require_relative 'client/protocol/requests/update'
require_relative 'client/protocol/requests/upsert'
require_relative 'client/protocol/requests/delete'
require_relative 'client/protocol/requests/call'
require_relative 'client/protocol/requests/eval'
require_relative 'client/protocol/requests/auth'
require_relative 'client/protocol/requests/id'
require_relative 'client/transport/future'
require_relative 'client/transport/pending_requests'
require_relative 'client/transport/deadline'
require_relative 'client/transport/frame_writer'
require_relative 'client/transport/connection'
require_relative 'client/schema'
require_relative 'client/operations'

module Tarantool
  # Connection to one Tarantool instance. Safe to share between threads and fibers.
  class Client
    include Operations

    attr_reader :config

    def initialize(uri = nil, **)
      @config = Configuration.build(uri, **)
      @connection = Transport::Connection.new(@config).connect
      @schema_lock = Mutex.new
      reload_schema
    rescue StandardError
      @connection&.close
      raise
    end

    def server_version
      @connection.greeting.version
    end

    def close
      @connection.close
    end

    private

    def perform(request, timeout: nil, schema_version: nil)
      @connection.perform(request, timeout: timeout || @config.request_timeout, schema_version:)
    end

    # Name-resolved requests carry the schema version they were resolved against, so the
    # server rejects them (ER_WRONG_SCHEMA_VERSION) instead of running them on a stale id.
    def perform_on_space(space, index, timeout: nil)
      return perform(yield(space, index), timeout:) if space.is_a?(Integer) && index.is_a?(Integer)

      schema, ids = resolve(@schema, space, index, timeout)
      perform(yield(*ids), timeout:, schema_version: schema.version)
    rescue ServerError => e
      raise unless e.code == Protocol::Constants::ER_WRONG_SCHEMA_VERSION

      schema, ids = resolve(reload_schema(schema, timeout:), space, index, timeout)
      perform(yield(*ids), timeout:, schema_version: schema.version)
    end

    def resolve(schema, space, index, timeout)
      [schema, schema.resolve(space, index)]
    rescue SchemaError
      schema = reload_schema(schema, timeout:)
      [schema, schema.resolve(space, index)]
    end

    def reload_schema(stale = nil, timeout: nil)
      @schema_lock.synchronize do
        return @schema unless @schema.equal?(stale)

        @schema = Schema.fetch(@connection, timeout: timeout || @config.request_timeout)
      end
    end
  end
end
