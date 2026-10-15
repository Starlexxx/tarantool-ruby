# frozen_string_literal: true

module Tarantool
  module Crud
    # Error returned by a crud function; the message is crud's err field.
    class Error < Tarantool::Error
      attr_reader :class_name, :str, :file, :line, :operation_data

      def self.from(error)
        CLASSES.fetch(error['class_name'], Error).new(
          error['err'],
          class_name: error['class_name'], str: error['str'], file: error['file'], line: error['line'],
          operation_data: error['operation_data']
        )
      end

      def initialize(message = nil, class_name: nil, str: nil, file: nil, line: nil, operation_data: nil)
        super(message)
        @class_name = class_name
        @str = str
        @file = file
        @line = line
        @operation_data = operation_data
      end
    end

    class InsertError < Error; end
    class ReplaceError < Error; end
    class UpsertError < Error; end
    class GetError < Error; end
    class UpdateError < Error; end
    class DeleteError < Error; end
    class SelectError < Error; end
    class CountError < Error; end
    class MinMaxError < Error; end
    class LenError < Error; end
    class TruncateError < Error; end

    # One row of a *_many call failed; operation_data holds that row.
    class CallError < Error; end

    # A whole *_many call failed before any row was processed.
    class InsertManyError < Error; end
    class ReplaceManyError < Error; end
    class UpsertManyError < Error; end

    class Error
      CLASSES = {
        'InsertError' => InsertError,
        'ReplaceError' => ReplaceError,
        'UpsertError' => UpsertError,
        'GetError' => GetError,
        'UpdateError' => UpdateError,
        'DeleteError' => DeleteError,
        'SelectError' => SelectError,
        'CountError' => CountError,
        'BorderError' => MinMaxError,
        'LenError' => LenError,
        'TruncateError' => TruncateError,
        'CallError' => CallError,
        'InsertManyError' => InsertManyError,
        'ReplaceManyError' => ReplaceManyError,
        'UpsertManyError' => UpsertManyError
      }.freeze
    end
  end
end
