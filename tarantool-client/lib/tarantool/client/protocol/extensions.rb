# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      # MP_EXT types the codec knows; every file under extensions/ registers itself here.
      module Extensions
        Entry = Data.define(:type, :klass, :options)

        @entries = []

        class << self
          include Enumerable

          def register(type, klass, **options)
            @entries << Entry.new(type:, klass:, options:)
          end

          def each(&)
            @entries.each(&)
          end
        end
      end
    end
  end
end
