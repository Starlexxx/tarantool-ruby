# frozen_string_literal: true

module Tarantool
  class Client
    # One page of a select asked with `fetch_position: true`: the tuples (converted by `as:`) and the position to
    # continue after with `after:`, nil when the page is empty. Opaque: tied to the index and iterator that
    # produced it.
    Page = Data.define(:tuples, :position) do
      include Enumerable

      def each(&) = tuples.each(&)

      def empty? = tuples.empty?

      def size = tuples.size
    end
  end
end
