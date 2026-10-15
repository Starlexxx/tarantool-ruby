# frozen_string_literal: true

module Tarantool
  class Client
    # A Tarantool datetime.interval; adjust is :none, :excess or :last.
    Interval = Data.define(:year, :month, :week, :day, :hour, :min, :sec, :nsec, :adjust) do
      def initialize(year: 0, month: 0, week: 0, day: 0, hour: 0, min: 0, sec: 0, nsec: 0, adjust: :none)
        super
      end
    end
  end
end
