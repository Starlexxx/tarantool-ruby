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
require_relative 'client/pool'
require_relative 'client/pool/member'

module Tarantool
  # Connection to one Tarantool instance. Safe to share between threads and fibers.
  class Client
    include Operations

    attr_reader :config

    # @api private
    # Called when the connection is lost, before the first reconnect attempt, then again on the watcher
    # dispatcher thread after every event of the lost connection and before any of the next one.
    attr_writer :disconnect_handler

    def initialize(uri = nil, **)
      @config = Configuration.build(uri, **)
      @link = Transport::Link.new(@config, **link_hooks)
      @watchers = Watchers.new(@link, timeout: @config.request_timeout)
      @link.event_handler = @watchers.method(:dispatch)
      @schema_cache = SchemaCache.new
      @stream_ids = Transport::StreamIds.new
      @link.connect
    rescue StandardError
      @link&.close
      raise
    end

    def server_version
      @link.greeting.version
    end

    def connected?
      @link.connected?
    end

    def transaction(isolation: :default, timeout: nil, &block)
      TransactionScope.enter(self) do
        stream = Stream.new(
          connection: @link.connection, schema_cache: @schema_cache, id: @stream_ids.next,
          request_timeout: @config.request_timeout
        )
        stream.transaction(isolation:, timeout:, &block)
      end
    end

    # The block gets the current value first (nil if the key was never broadcast), then every
    # change. It runs on a dispatcher thread shared by all watchers of this client, so a slow
    # block delays the others; exceptions it raises are reported with warn. Calling #unwatch
    # from another thread may still let one in-flight callback run. After a reconnect the block
    # is called again with the current value.
    def watch(key, &block)
      raise ArgumentError, 'watch requires a block' unless block

      @watchers.add(key, block)
    end

    def close
      @link.close
      @watchers.close
    end

    def inspect
      "#<#{self.class.name} #{@config.address}>"
    end

    private

    def link_hooks = { on_connect: method(:load_schema), on_ready: method(:resubscribe), on_lost: method(:lost) }

    def perform(request, timeout: nil, schema_version: nil, on_push: nil)
      @link.perform(request, timeout: timeout || @config.request_timeout, schema_version:, on_push:)
    end

    # Runs for every new connection before requests can use it. A new instance may reuse a schema
    # version with other ids, so the old schema must never resolve a name for it.
    def load_schema(connection)
      @schema_cache.replace(Schema.fetch(connection, timeout: @config.request_timeout))
    end

    def resubscribe(connection)
      @watchers.resubscribe(connection)
    end

    def lost
      return unless @disconnect_handler

      @disconnect_handler.call
      @watchers.defer(&@disconnect_handler)
    end

    # Name-resolved requests carry the schema version they were resolved against, so the
    # server rejects them (ER_WRONG_SCHEMA_VERSION) instead of running them on a stale id.
    def perform_on_space(space, index, timeout: nil, &)
      return perform(yield(space, index), timeout:) if space.is_a?(Integer) && index.is_a?(Integer)

      perform_by_name(space, index, timeout || @config.request_timeout, &)
    end

    # Every schema fetch and attempt draws on one deadline, so the whole call stays within timeout.
    # Waiting for a connection first means the cache already holds its schema or a newer one.
    def perform_by_name(space, index, timeout, &)
      deadline = Transport::Deadline.after(timeout)
      @link.connection(deadline)
      perform_with_schema_check(space, index, deadline, &)
    rescue TimeoutError
      raise TimeoutError, "no response within #{timeout}s"
    end

    def perform_with_schema_check(space, index, deadline)
      schema, ids = @schema_cache.resolve(space, index, deadline)
      perform_resolved(schema, yield(*ids), deadline)
    rescue ServerError => e
      raise unless e.code == Protocol::Constants::ER_WRONG_SCHEMA_VERSION

      fresh = @schema_cache.reload(schema, timeout: Transport::Deadline.remaining(deadline))
      schema, ids = @schema_cache.resolve(space, index, deadline, fresh)
      perform_resolved(schema, yield(*ids), deadline)
    end

    # Only the connection the schema came from: once it is lost, another instance may reuse the
    # schema version with other ids, so the request fails with it rather than wait for a reconnect.
    def perform_resolved(schema, request, deadline)
      timeout = Transport::Deadline.remaining(deadline)
      schema.connection.perform(request, timeout:, schema_version: schema.version)
    end
  end
end
