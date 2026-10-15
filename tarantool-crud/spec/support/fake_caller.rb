# frozen_string_literal: true

# Stands in for Tarantool::Client: records calls and replays responses, repeating the last one.
class FakeCaller
  Request = Data.define(:function, :arguments, :timeout)

  attr_reader :requests

  def initialize(*responses)
    @responses = responses
    @requests = []
  end

  def call(function, arguments, timeout: nil)
    @requests << Request.new(function:, arguments:, timeout:)
    @responses.size > 1 ? @responses.shift : @responses.first
  end

  def last = @requests.last
end
