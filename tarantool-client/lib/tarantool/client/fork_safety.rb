# frozen_string_literal: true

module Tarantool
  class Client
    # A client created before fork reopens its link in the child on first use: the parent's reader, reconnect
    # and dispatcher threads don't exist there. Closing the inherited socket in the child sends nothing.
    # @api private
    module ForkSafety
      private

      def ensure_fork_safe
        return if @pid == Process.pid

        @reinit_lock.synchronize { reopen_after_fork unless @pid == Process.pid }
      end

      def reopen_after_fork
        close_inherited_link
        open_link
        @instrumentation&.notify('fork.tarantool')
      end

      # Joining a thread that died with an exception re-raises it; nothing from the parent may stop the reopen.
      def close_inherited_link
        @link.close
      rescue StandardError
        nil
      end

      # Watcher registrations outlive a fork; on_ready resubscribes them on the new link, the shutdown
      # subscription among them.
      def open_link
        @link = Transport::Link.new(@config, instrumentation: @instrumentation, **link_hooks)
        @watchers&.restart_after_fork(@link)
        first = @watchers.nil?
        @watchers ||= Watchers.new(@link, timeout: @config.request_timeout)
        @link.event_handler = @watchers.method(:dispatch)
        @schema_cache = SchemaCache.new
        @stream_ids = Transport::StreamIds.new
        @link.connect
        @pid = Process.pid
        subscribe_to_shutdown if first
      end

      # box.shutdown is true once the server starts stopping; the value on subscribing is nil before that.
      def subscribe_to_shutdown
        @watchers.add('box.shutdown', ->(_key, value) { @link.drain if value })
      end
    end
  end
end
