# frozen_string_literal: true

module Tarantool
  class Client
    # Requests whose space and index resolve through the schema cache. Includers set @link, @schema_cache and
    # @config, and provide ensure_fork_safe and mark_schema_reloaded.
    # @api private
    module NamedRequests
      private

      # Every schema fetch and attempt draws on one deadline, so the whole call stays within timeout.
      # Waiting for a connection first means the cache already holds its schema or a newer one.
      def perform_by_name(space, index, timeout, payload, &)
        ensure_fork_safe
        deadline = Transport::Deadline.after(timeout)
        @link.connection(deadline)

        perform_with_schema_check(space, index, deadline, payload, &)
      rescue TimeoutError
        raise TimeoutError, "no response within #{timeout}s"
      end

      def lookup_space(space, timeout)
        ensure_fork_safe
        timeout ||= @config.request_timeout
        deadline = Transport::Deadline.after(timeout)
        @link.connection(deadline)

        @schema_cache.space_info(space, deadline)
      rescue TimeoutError
        raise TimeoutError, "no response within #{timeout}s"
      end

      def perform_with_schema_check(space, index, deadline, payload, &)
        schema, ids = resolve_name(space, index, deadline, payload)

        perform_built(schema, ids, deadline, &)
      rescue ServerError, UnknownFieldError => e
        raise if e.is_a?(ServerError) && e.code != Protocol::Constants::ER_WRONG_SCHEMA_VERSION

        mark_schema_reloaded(payload)
        fresh = @schema_cache.reload(schema, timeout: Transport::Deadline.remaining(deadline))
        schema, ids = resolve_name(space, index, deadline, payload, fresh)
        perform_built(schema, ids, deadline, &)
      end

      def perform_built(schema, ids, deadline)
        perform_resolved(schema, yield(*ids, schema.space_info(ids.first)), deadline)
      end

      # The cache returns another schema only when resolving had to reload it.
      def resolve_name(space, index, deadline, payload, schema = @schema_cache.schema)
        resolved, ids = @schema_cache.resolve(space, index, deadline, schema)
        mark_schema_reloaded(payload) unless resolved.equal?(schema)

        [resolved, ids]
      end

      # Only the connection the schema came from: once it is lost, another instance may reuse the
      # schema version with other ids, so the request fails with it rather than wait for a reconnect.
      def perform_resolved(schema, request, deadline)
        timeout = Transport::Deadline.remaining(deadline)

        schema.connection.perform(request, timeout:, schema_version: schema.version)
      end
    end
  end
end
