# frozen_string_literal: true

module Tarantool
  class Client
    class Watchers
      # Runs jobs in order on one thread, started by the first job and again by the first one after it died.
      # Close drops the jobs still queued.
      # @api private
      class Dispatcher
        def initialize
          @lock = Mutex.new
          @jobs = Thread::Queue.new
        end

        def push(&job)
          @lock.synchronize do
            @thread = Thread.new { run }.tap { |thread| thread.name = 'tarantool-watchers' } unless @thread&.alive?
          end

          @jobs.push(job)
        end

        def close
          @jobs.clear
          @jobs.close

          ThreadJoin.join(@thread)
        end

        private

        def run
          while (job = @jobs.pop)
            job.call
          end
        end
      end
    end
  end
end
