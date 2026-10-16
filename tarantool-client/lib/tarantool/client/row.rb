# frozen_string_literal: true

module Tarantool
  class Client
    # A tuple as the server returned it, with its fields by name (SpaceInfo#to_hash). Returned for `as: :row`.
    Row = Data.define(:tuple, :attributes)
  end
end
