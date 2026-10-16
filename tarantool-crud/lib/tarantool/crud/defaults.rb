# frozen_string_literal: true

module Tarantool
  module Crud
    # Client-wide read and write options. crud rejects options a function does not know, so defaults are
    # narrowed to what each function accepts (crud 1.8.0); options given to a call are sent as is.
    # @api private
    class Defaults
      READ_FUNCTIONS = %w[get select count min max len storage_info stats].freeze

      READ = %i[timeout request_timeout bucket_id prefer_replica balance mode vshard_router].freeze
      BORDERS = %i[timeout request_timeout fields mode vshard_router fetch_latest_metadata].freeze
      SERVICE = %i[timeout vshard_router].freeze
      WRITE = %i[timeout bucket_id fields vshard_router noreturn fetch_latest_metadata].freeze
      TUPLE = (WRITE + %i[add_space_schema_hash]).freeze
      OBJECT = (TUPLE + %i[skip_nullability_check_on_flatten]).freeze
      MANY = %i[timeout fields stop_on_error rollback_on_error vshard_router noreturn fetch_latest_metadata].freeze
      TUPLE_MANY = (MANY + %i[add_space_schema_hash]).freeze
      OBJECT_MANY = (MANY + %i[skip_nullability_check_on_flatten]).freeze

      ACCEPTED = {
        'get' => READ + %i[fields fetch_latest_metadata],
        'select' => READ + %i[after first batch_size force_map_call fields fullscan fetch_latest_metadata
                              readview readview_info yield_every],
        'count' => READ + %i[force_map_call fullscan yield_every],
        'min' => BORDERS,
        'max' => BORDERS,
        'len' => READ - %i[bucket_id],
        'storage_info' => SERVICE,
        'stats' => %i[timeout],
        'truncate' => SERVICE,
        'insert' => TUPLE,
        'insert_object' => OBJECT,
        'replace' => TUPLE,
        'replace_object' => OBJECT,
        'upsert' => TUPLE,
        'upsert_object' => TUPLE,
        'update' => WRITE,
        'delete' => WRITE,
        'insert_many' => TUPLE_MANY,
        'insert_object_many' => OBJECT_MANY,
        'replace_many' => TUPLE_MANY,
        'replace_object_many' => OBJECT_MANY,
        'upsert_many' => TUPLE_MANY,
        'upsert_object_many' => MANY
      }.freeze

      def initialize(read:, write:)
        @read = read
        @write = write
      end

      def options_for(function)
        (READ_FUNCTIONS.include?(function) ? @read : @write).slice(*ACCEPTED.fetch(function))
      end
    end
  end
end
