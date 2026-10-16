# frozen_string_literal: true

module Tarantool
  class Client
    # Operations sent over one IPROTO stream inside an interactive transaction; the server runs a
    # stream's requests in order. Created by Client#transaction.
    class Stream
      include Operations
      include Instrumented

      LOST = 'connection lost during the transaction; the server rolled it back'
      FINISHED = 'transaction is finished'

      def initialize(connection:, schema_cache:, id:, request_timeout:, instrumentation: nil)
        @connection = connection
        @schema_cache = schema_cache
        @id = id
        @request_timeout = request_timeout
        @instrumentation = instrumentation
        @state = :idle
        @pid = Process.pid
      end

      def transaction(isolation:, timeout:, &)
        raise TransactionError, TransactionScope::NESTED unless @state == :idle

        start(isolation, timeout)

        run(&)
      end

      def prepare(*)
        raise TransactionError,
              'prepare statements on the client; execute them in the transaction with tx.execute(statement, bindings)'
      end

      private

      def start(isolation, timeout)
        response = perform(Protocol::Requests::Begin.new(isolation:, timeout:))
        @schema = TransactionSchema.new(@schema_cache, @connection, response.schema_version)

        @state = :active
      end

      # Anything but normal completion of the block, including break and throw, rolls back.
      def run
        result = yield self
        finish(Protocol::Requests::Commit.new)

        result
      ensure
        abandon if @state == :active
      end

      def transmit(request, timeout: nil, schema_version: nil, on_push: nil)
        check_active

        send_request(request, timeout: timeout || @request_timeout, schema_version:, on_push:)
      end

      def transmit_on_space(space, index, timeout: nil, format: false, payload: nil, &)
        return transmit(yield(space, index), timeout:) if !format && space.is_a?(Integer) && index.is_a?(Integer)

        perform_by_name(space, index, timeout || @request_timeout, payload, &)
      end

      # Checks for a lost connection first: resolving would otherwise meet the next connection's schema
      # and report a schema change instead.
      def perform_by_name(space, index, timeout, payload, &)
        check_connection
        deadline = Transport::Deadline.after(timeout)
        request = build_request(space, index, deadline, payload, &)

        transmit(request, timeout: remaining(deadline), schema_version: @schema.version)
      rescue ServerError => e
        raise unless e.code == Protocol::Constants::ER_WRONG_SCHEMA_VERSION

        mark_schema_reloaded(payload) if @schema.refresh?(deadline)
        raise TransactionError, TransactionSchema::CHANGED
      rescue TimeoutError
        raise TimeoutError, "no response within #{timeout}s"
      end

      def build_request(space, index, deadline, payload)
        (space_id, index_id), reloaded = @schema.resolve(space, index, deadline)
        mark_schema_reloaded(payload) if reloaded

        yield(space_id, index_id, @schema.space_info(space_id, deadline))
      end

      def lookup_space(space, timeout)
        check_active
        check_connection
        timeout ||= @request_timeout

        @schema.space_info(space, Transport::Deadline.after(timeout))
      rescue TimeoutError
        raise TimeoutError, "no response within #{timeout}s"
      end

      def remaining(deadline)
        Transport::Deadline.remaining(deadline)
      end

      # State flips to finished before the request so a failed COMMIT is not followed by ROLLBACK:
      # its outcome is unknown (the server may have committed), and a rollback would add nothing.
      def finish(request)
        @state = :finished

        instrumented(request) { send_request(request, timeout: @request_timeout) }
      end

      # A stream is bound to its connection's session, so a reconnect can't carry the transaction over.
      def send_request(request, **)
        check_connection

        @connection.perform(request, stream_id: @id, **)
      end

      def check_connection
        raise ConnectionError, 'stream was created before fork and cannot be used in a child process' \
          if Process.pid != @pid
        raise TransactionError, LOST if @state != :idle && @connection.closed?
      end

      def check_active
        raise TransactionError, FINISHED if @state == :finished
      end

      # Runs while an error or a non-local exit is already propagating, which a failed rollback must
      # not replace. A lost connection takes the transaction with it.
      def abandon
        finish(Protocol::Requests::Rollback.new)
      rescue Error
        nil
      end
    end
  end
end
