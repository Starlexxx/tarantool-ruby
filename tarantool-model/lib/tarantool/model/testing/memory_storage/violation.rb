# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # What the server would reject, with its error code and text. Never leaves MemoryStorage: the mode turns it
        # into the error class the application sees in production. `kind` is :space, :index, :nil_field or :server.
        # @api private
        class Violation < StandardError
          attr_reader :kind, :code, :subject

          def self.nil_field(fieldno, field)
            new("Tuple field #{fieldno + 1} (#{field.name}) type does not match one required by operation: " \
                "expected #{field.type}, got nil", kind: :nil_field, code: 23, subject: field.name)
          end

          def self.primary_key_update(space)
            new("Attempt to modify a tuple field which is part of primary index in space '#{space}'", code: 94)
          end

          def self.operand(operator, name)
            new("Argument type in operation '#{operator}' on field '#{name}' does not match field type: " \
                'expected a number', code: 26)
          end

          def self.unknown_field(name)
            new("Field '#{name}' was not found in the tuple", code: 201)
          end

          def self.key_part_count(max, got)
            new("Invalid key part count (expected [0..#{max}], got #{got})", code: 31)
          end

          def self.iterator(index, space)
            new("Index '#{index}' (HASH) of space '#{space}' (memtx) does not support requested iterator type",
                code: 112)
          end

          def self.pagination(index, space)
            new("Index '#{index}' (HASH) of space '#{space}' (memtx) does not support pagination", code: 112)
          end

          def self.unknown_space(name)
            new("space '#{name}' not found", kind: :space, subject: name)
          end

          def self.unknown_index(index, space)
            new("index '#{index}' not found in space #{space}", kind: :index, subject: index)
          end

          def initialize(message, kind: :server, code: nil, subject: nil)
            super(message)
            @kind = kind
            @code = code
            @subject = subject
          end
        end
      end
    end
  end
end
