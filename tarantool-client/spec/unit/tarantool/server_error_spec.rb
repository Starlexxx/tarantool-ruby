# frozen_string_literal: true

RSpec.describe Tarantool::ServerError do
  describe '.from_response' do
    let(:response_class) { Data.define(:error_message, :error_code, :error_stack, :schema_version) }

    it 'builds an error from a response' do
      response = response_class.new(error_message: 'boom', error_code: 42, error_stack: %w[a b], schema_version: 80)

      error = described_class.from_response(response)

      expect(error).to have_attributes(message: 'boom', code: 42, error_stack: %w[a b], schema_version: 80)
    end

    it 'leaves the schema version nil when the response has none' do
      response = response_class.new(error_message: 'boom', error_code: 42, error_stack: [], schema_version: nil)

      expect(described_class.from_response(response).schema_version).to be_nil
    end
  end
end
