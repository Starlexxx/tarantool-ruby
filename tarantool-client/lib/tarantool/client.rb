# frozen_string_literal: true

require 'msgpack'

require_relative 'client/version'
require_relative 'client/errors'
require_relative 'client/configuration'
require_relative 'client/backoff'
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
require_relative 'client/protocol/requests/execute'
require_relative 'client/protocol/requests/prepare'
require_relative 'client/protocol/requests/begin'
require_relative 'client/protocol/requests/commit'
require_relative 'client/protocol/requests/rollback'
require_relative 'client/protocol/requests/auth'
require_relative 'client/protocol/requests/id'
require_relative 'client/protocol/requests/watch'
require_relative 'client/protocol/requests/unwatch'
require_relative 'client/transport/future'
require_relative 'client/transport/pending_requests'
require_relative 'client/transport/stream_ids'
require_relative 'client/transport/deadline'
require_relative 'client/transport/timed_lock'
require_relative 'client/transport/frame_writer'
require_relative 'client/transport/handshake'
require_relative 'client/transport/connection'
require_relative 'client/transport/link_state'
require_relative 'client/transport/link'
require_relative 'client/schema'
require_relative 'client/schema_cache'
require_relative 'client/sql_result'
require_relative 'client/prepared_statement'
require_relative 'client/transaction_schema'
require_relative 'client/operations'
require_relative 'client/transaction_scope'
require_relative 'client/stream'
require_relative 'client/watcher'
require_relative 'client/watchers'

module Tarantool
  # Connection to one Tarantool instance. Safe to share between threads and fibers.
  class Client
    include Operations

    attr_reader :config

    def initialize(uri = nil, **)
      @config = Configuration.build(uri, **)
      @connection = Transport::Connection.new(@config)
      @watchers = Watchers.new(@connection, timeout: @config.request_timeout)
      @connection.event_handler = @watchers.method(:dispatch)
      @connection.connect
      @schema_cache = SchemaCache.new(@connection).tap { |cache| cache.reload(timeout: @config.request_timeout) }
      @stream_ids = Transport::StreamIds.new
    rescue StandardError
      @connection&.close
      raise
    end

    def server_version
      @connection.greeting.version
    end

    def transaction(isolation: :default, timeout: nil, &block)
      TransactionScope.enter(self) do
        stream = Stream.new(
          connection: @connection, schema_cache: @schema_cache, id: @stream_ids.next,
          request_timeout: @config.request_timeout
        )
        stream.transaction(isolation:, timeout:, &block)
      end
    end

    # The block gets the current value first (nil if the key was never broadcast), then every
    # change. It runs on a dispatcher thread shared by all watchers of this client, so a slow
    # block delays the others; exceptions it raises are reported with warn. Calling #unwatch
    # from another thread may still let one in-flight callback run.
    def watch(key, &block)
      raise ArgumentError, 'watch requires a block' unless block

      @watchers.add(key, block)
    end

    def close
      @connection.close
      @watchers.close
    end

    def inspect
      "#<#{self.class.name} #{@config.address}>"
    end

    private

    def perform(request, timeout: nil, schema_version: nil, on_push: nil)
      @connection.perform(request, timeout: timeout || @config.request_timeout, schema_version:, on_push:)
    end

    # Name-resolved requests carry the schema version they were resolved against, so the
    # server rejects them (ER_WRONG_SCHEMA_VERSION) instead of running them on a stale id.
    def perform_on_space(space, index, timeout: nil, &)
      return perform(yield(space, index), timeout:) if space.is_a?(Integer) && index.is_a?(Integer)

      perform_by_name(space, index, timeout || @config.request_timeout, &)
    end

    # Every schema fetch and attempt draws on one deadline, so the whole call stays within timeout.
    def perform_by_name(space, index, timeout, &)
      perform_with_schema_check(space, index, Transport::Deadline.after(timeout), &)
    rescue TimeoutError
      raise TimeoutError, "no response within #{timeout}s"
    end

    def perform_with_schema_check(space, index, deadline)
      schema, ids = @schema_cache.resolve(space, index, deadline)
      perform(yield(*ids), timeout: Transport::Deadline.remaining(deadline), schema_version: schema.version)
    rescue ServerError => e
      raise unless e.code == Protocol::Constants::ER_WRONG_SCHEMA_VERSION

      fresh = @schema_cache.reload(schema, timeout: Transport::Deadline.remaining(deadline))
      schema, ids = @schema_cache.resolve(space, index, deadline, fresh)
      perform(yield(*ids), timeout: Transport::Deadline.remaining(deadline), schema_version: schema.version)
    end
  end
end
