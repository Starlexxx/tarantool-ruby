# frozen_string_literal: true

module Tarantool
  module Model
    # An immutable query over one index condition. The query runs on every enumeration; results are not cached.
    # Order is the index order (descending for :le/:lt); pagination is keyset only, with #after.
    class Relation
      include Enumerable

      DEFAULTS = { index: nil, key: [], iterator: :all, limit: nil, after: nil, filtered: false }.freeze
      QUERY = %i[index key iterator].freeze

      def initialize(model, **options)
        @model = model
        @options = DEFAULTS.merge(options).freeze
        freeze
      end

      def where(index: nil, key: [], iterator: :eq)
        raise ArgumentError, 'a relation takes one index condition, where was already called' if @options[:filtered]

        spawn(index:, key: Key.wrap(key), iterator:, filtered: true)
      end

      def limit(count)
        spawn(limit: count)
      end

      def after(record)
        raise ArgumentError, "#{record.class.name} has no tuple to continue after" unless record.tuple

        spawn(after: record.tuple)
      end

      def each
        return enum_for(:each) unless block_given?

        rows.each { |row| yield @model.instantiate(row) }
      end

      def first(count = nil)
        count ? limit(count).to_a : limit(1).to_a.first
      end

      # Every match of the index condition: limit and after are ignored.
      # With a block or argument, delegates to Enumerable#count (enumerates).
      def count(*args, &block)
        return @model.verified_storage.count(@model.space_name, **@options.slice(*QUERY)) if args.empty? && !block

        super
      end

      def find_each(batch_size: 1000, &block)
        return enum_for(:find_each, batch_size:) unless block

        relation = limit(batch_size)

        loop do
          batch = relation.to_a
          batch.each(&block)
          break if batch.size < batch_size

          relation = relation.after(batch.last)
        end
      end

      private

      def rows
        @model.verified_storage.select(@model.space_name, **@options.slice(*QUERY, :limit, :after))
      end

      def spawn(**changes)
        self.class.new(@model, **@options, **changes)
      end
    end
  end
end
