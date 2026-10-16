# frozen_string_literal: true

module Tarantool
  class Client
    # Per-process reinit for forked children. Included in Client.
    # @api private
    module ForkSafety
      private

      # Hot path: one integer comparison. Reinitializes once in a forked child.
      # Parent threads are dead after fork so their joins in close return immediately.
      # Double-checked locking ensures only one reinit even with concurrent child threads.
      def ensure_fork_safe
        return if @pid == Process.pid

        @reinit_lock.synchronize { fork_reinit unless @pid == Process.pid }
      rescue StandardError
        @link&.close
        raise
      end

      # Replaces per-process resources (link, schema cache, stream IDs). Watcher registrations
      # are preserved via restart_after_fork: the new link's on_ready resubscribes all keys so
      # callbacks receive the current value again. open_link builds a brand-new Watchers at init;
      # fork_reinit reuses the existing one so pre-fork watchers survive the child.
      def fork_reinit
        try_close(@link)
        @schema_cache = SchemaCache.new
        @stream_ids = Transport::StreamIds.new
        @link = Transport::Link.new(@config, **link_hooks)
        @link.event_handler = @watchers.method(:dispatch)
        @watchers.restart_after_fork(@link)
        @link.connect
        @pid = Process.pid
      end

      def open_link
        @link = Transport::Link.new(@config, **link_hooks)
        @watchers = Watchers.new(@link, timeout: @config.request_timeout)
        @link.event_handler = @watchers.method(:dispatch)
        @schema_cache = SchemaCache.new
        @stream_ids = Transport::StreamIds.new
        @link.connect
        @pid = Process.pid
      end

      def try_close(obj)
        obj.close
      rescue StandardError
        nil
      end
    end
  end
end
