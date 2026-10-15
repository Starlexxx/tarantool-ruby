# frozen_string_literal: true

module Tarantool
  class Client
    # Operations sent over one IPROTO stream inside an interactive transaction; the server runs a
    # stream's requests in order. Created by Client#transaction.
    class Stream
      include Operations

      def initialize(connection:, schema_cache:, id:, request_timeout:)
        @connection = connection
        @schema_cache = schema_cache
        @id = id
        @request_timeout = request_timeout
        @state = :idle
      end

      def transaction(isolation:, timeout:, &)
        raise TransactionError, TransactionScope::NESTED unless @state == :idle

        start(isolation, timeout)
        run(&)
      end

      private

      def start(isolation, timeout)
        response = perform(Protocol::Requests::Begin.new(isolation:, timeout:))
        @schema = TransactionSchema.new(@schema_cache, response.schema_version)
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

      def perform(request, timeout: nil, schema_version: nil)
        raise TransactionError, 'transaction is finished' if @state == :finished

        @connection.perform(request, timeout: timeout || @request_timeout, stream_id: @id, schema_version:)
      end

      def perform_on_space(space, index, timeout: nil, &)
        return perform(yield(space, index), timeout:) if space.is_a?(Integer) && index.is_a?(Integer)

        perform_by_name(space, index, timeout || @request_timeout, &)
      end

      def perform_by_name(space, index, timeout)
        deadline = Transport::Deadline.after(timeout)
        request = yield(*@schema.resolve(space, index, deadline))
        perform(request, timeout: remaining(deadline), schema_version: @schema.version)
      rescue ServerError => e
        raise unless e.code == Protocol::Constants::ER_WRONG_SCHEMA_VERSION

        @schema.raise_changed(deadline)
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
        @connection.perform(request, timeout: @request_timeout, stream_id: @id)
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
