# frozen_string_literal: true

module Tarantool
  class Client
    # Runs user code on the shared watcher dispatcher, which must outlive whatever that code raises. Exit and
    # signals go to the main thread, where they would have ended the process without the dispatcher;
    # NoMemoryError still ends the worker, and the next job starts a new one.
    # @api private
    module CallbackGuard
      module_function

      def run(description)
        yield
      rescue SystemExit, SignalException => e
        Thread.main.raise(e)
      rescue NoMemoryError
        raise
      rescue Exception => e
        warn("#{description} failed: #{e.class}: #{e.message}")
      end
    end
  end
end
