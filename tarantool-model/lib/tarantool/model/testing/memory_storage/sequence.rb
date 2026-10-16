# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # The sequence of a primary key field: fills nil from 1 and moves past explicit Integer values. Never
        # restored by a rollback, as in Tarantool.
        # @api private
        class Sequence
          def initialize(fieldno)
            @fieldno = fieldno
            @counter = 0
          end

          def fill(tuple)
            value = tuple[@fieldno]
            if value.nil?
              tuple[@fieldno] = @counter += 1
            elsif value.is_a?(Integer)
              @counter = [@counter, value].max
            end
          end
        end
      end
    end
  end
end
