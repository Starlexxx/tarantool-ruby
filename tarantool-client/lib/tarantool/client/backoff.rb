# frozen_string_literal: true

module Tarantool
  class Client
    # Exponential backoff with full jitter: the delay before attempt n is uniformly random in
    # [0, min(max, base * 2**n)), so clients that lost the same server don't reconnect in lockstep.
    class Backoff
      # Keeps 2**n small for endless retries; the cap is reached long before.
      MAX_EXPONENT = 32

      def initialize(base:, max:, random: Random.new)
        @base = base
        @max = max
        @random = random
      end

      def delay(attempt)
        @random.rand * [@max, @base * (2**[attempt, MAX_EXPONENT].min)].min
      end
    end
  end
end
