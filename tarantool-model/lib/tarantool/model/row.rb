# frozen_string_literal: true

module Tarantool
  module Model
    # What a storage returns for one row: attributes by Symbol name, and the raw tuple as the server returned it,
    # or nil when the storage has none.
    # @api private
    Row = Data.define(:attributes, :tuple)
  end
end
