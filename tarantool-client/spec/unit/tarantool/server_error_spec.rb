# frozen_string_literal: true

RSpec.describe Tarantool::ServerError do
  describe '.from_response' do
    it 'builds an error from a response' do
      response_class = Data.define(:error_message, :error_code, :error_stack)
      response = response_class.new(error_message: 'boom', error_code: 42, error_stack: %w[a b])

      error = described_class.from_response(response)

      expect(error.message).to eq('boom')
      expect(error.code).to eq(42)
      expect(error.error_stack).to eq(%w[a b])
    end
  end
end
