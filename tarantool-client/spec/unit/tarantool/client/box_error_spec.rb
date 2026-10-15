# frozen_string_literal: true

RSpec.describe Tarantool::Client::BoxError do
  describe '.from_stack' do
    let(:stack) do
      [
        { 0x00 => 'ClientError', 0x01 => 'eval', 0x02 => 1, 0x03 => 'boom', 0x04 => 0, 0x05 => 42,
          0x06 => { 'name' => 'ACCESS_DENIED' } },
        { 0x00 => 'ClientError', 0x03 => 'root', 0x05 => 7 }
      ]
    end

    it 'builds the top error from the first entry' do
      expect(described_class.from_stack(stack)).to have_attributes(
        type: 'ClientError', file: 'eval', line: 1, message: 'boom', errno: 0, code: 42,
        fields: { 'name' => 'ACCESS_DENIED' }
      )
    end

    it 'links the following entries as causes' do
      cause = described_class.from_stack(stack).cause

      expect(cause).to have_attributes(message: 'root', code: 7, file: nil, line: nil, cause: nil)
    end

    it 'returns nil for an empty stack' do
      expect(described_class.from_stack([])).to be_nil
    end
  end
end
