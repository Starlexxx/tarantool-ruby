# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # Rows of one space keyed by primary key, with the checks Tarantool makes on write.
        # @api private
        class Space
          attr_reader :info, :layout

          def initialize(info, sequence:)
            @info = info
            @layout = Storage::Box::Layout.new(info)
            @primary = info.primary_index
            @sequence = sequence
            @rows = {}
          end
        end
      end
    end
  end
end
