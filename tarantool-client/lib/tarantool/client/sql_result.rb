# frozen_string_literal: true

module Tarantool
  class Client
    # Rows and column names of an SQL query, or the counters of a data-changing statement.
    SqlResult = Data.define(:rows, :columns, :row_count, :autoincrement_ids) do
      def self.from_response(response)
        info = response.body.fetch(Protocol::Constants::SQL_INFO, {})

        new(
          rows: response.data || [],
          columns: column_names(response.body),
          row_count: info[Protocol::Constants::SQL_INFO_ROW_COUNT],
          autoincrement_ids: info.fetch(Protocol::Constants::SQL_INFO_AUTOINCREMENT_IDS, [])
        )
      end

      def self.column_names(body)
        body.fetch(Protocol::Constants::METADATA, []).map { |field| field.fetch(Protocol::Constants::FIELD_NAME) }
      end
      private_class_method :column_names
    end
  end
end
