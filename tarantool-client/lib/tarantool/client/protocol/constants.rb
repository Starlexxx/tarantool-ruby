# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      # IPROTO keys and codes: https://www.tarantool.io/en/doc/latest/reference/internals/iproto/keys/
      module Constants
        REQUEST_TYPE = 0x00
        SYNC = 0x01
        SCHEMA_VERSION = 0x05
        STREAM_ID = 0x0a

        SPACE_ID = 0x10
        INDEX_ID = 0x11
        LIMIT = 0x12
        OFFSET = 0x13
        ITERATOR = 0x14
        KEY = 0x20
        TUPLE = 0x21
        FUNCTION_NAME = 0x22
        USER_NAME = 0x23
        EXPR = 0x27
        OPS = 0x28
        AFTER_TUPLE = 0x2f
        DATA = 0x30
        ERROR_24 = 0x31
        METADATA = 0x32
        SQL_TEXT = 0x40
        SQL_BIND = 0x41
        SQL_INFO = 0x42
        STMT_ID = 0x43
        ERROR = 0x52
        VERSION = 0x54
        FEATURES = 0x55
        TIMEOUT = 0x56
        EVENT_KEY = 0x57
        EVENT_DATA = 0x58
        TXN_ISOLATION = 0x59

        OK = 0x00
        SELECT = 0x01
        INSERT = 0x02
        REPLACE = 0x03
        UPDATE = 0x04
        DELETE = 0x05
        AUTH = 0x07
        EVAL = 0x08
        UPSERT = 0x09
        CALL = 0x0a
        EXECUTE = 0x0b
        PREPARE = 0x0d
        BEGIN_TRANSACTION = 0x0e
        COMMIT = 0x0f
        ROLLBACK = 0x10
        PING = 0x40
        ID = 0x49
        WATCH = 0x4a
        UNWATCH = 0x4b
        EVENT = 0x4c
        CHUNK = 0x80
        TYPE_ERROR = 0x8000

        ER_WRONG_SCHEMA_VERSION = 109

        FIELD_NAME = 0x00
        SQL_INFO_ROW_COUNT = 0x00
        SQL_INFO_AUTOINCREMENT_IDS = 0x01

        MP_DECIMAL = 0x01
        MP_UUID = 0x02
        MP_ERROR = 0x03
        MP_DATETIME = 0x04
        MP_INTERVAL = 0x06
        ERROR_STACK = 0x00
        ERROR_FIELDS = {
          0x00 => :type, 0x01 => :file, 0x02 => :line, 0x03 => :message,
          0x04 => :errno, 0x05 => :code, 0x06 => :fields
        }.freeze

        ITERATORS = {
          eq: 0, req: 1, all: 2, lt: 3, le: 4, ge: 5, gt: 6,
          bits_all_set: 7, bits_any_set: 8, bits_all_not_set: 9, overlaps: 10, neighbor: 11,
          np: 12, pp: 13
        }.freeze

        ISOLATION_LEVELS = { default: 0, read_committed: 1, read_confirmed: 2, best_effort: 3, linearizable: 4 }.freeze

        PROTOCOL_VERSION = 3
        FEATURE_STREAMS = 0
        FEATURE_TRANSACTIONS = 1
        FEATURE_ERROR_EXTENSION = 2
        FEATURE_WATCHERS = 3
        CLIENT_FEATURES = [FEATURE_STREAMS, FEATURE_TRANSACTIONS, FEATURE_ERROR_EXTENSION, FEATURE_WATCHERS].freeze

        GREETING_SIZE = 128
        SCRAMBLE_SIZE = 20
        MAX_LIMIT = 0xffff_ffff
        VSPACE_ID = 281
        VINDEX_ID = 289
      end
    end
  end
end
