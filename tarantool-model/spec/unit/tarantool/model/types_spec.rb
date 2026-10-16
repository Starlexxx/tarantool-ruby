# frozen_string_literal: true

RSpec.describe Tarantool::Model::Types do
  describe Tarantool::Model::Types::UUID do
    subject(:type) { described_class.new }

    let(:value) { 'A7F0C3B2-1D4E-4F5A-9B6C-0D1E2F3A4B5C' }

    it 'casts a String to Client::UUID' do
      expect(type.cast(value)).to eq(Tarantool::Client::UUID.new(value:))
    end

    it 'keeps a Client::UUID and nil' do
      uuid = Tarantool::Client::UUID.new(value:)

      expect([type.cast(uuid), type.cast(nil)]).to eq([uuid, nil])
    end

    it 'casts a malformed String to nil' do
      expect(type.cast('not-a-uuid')).to be_nil
    end
  end

  describe Tarantool::Model::Types::Interval do
    subject(:type) { described_class.new }

    it 'keeps a Client::Interval and builds one from a Hash' do
      interval = Tarantool::Client::Interval.new(day: 1)

      expect([type.cast(interval), type.cast({ 'day' => 1 })]).to eq([interval, interval])
    end
  end

  describe Tarantool::Model::Types::Binary do
    subject(:type) { described_class.new }

    it 'casts a String to ASCII-8BIT without changing the original' do
      original = +'é'

      expect(type.cast(original).encoding).to eq(Encoding::BINARY)
      expect(original.encoding).to eq(Encoding::UTF_8)
    end
  end

  it 'leaves the global ActiveModel::Type registry alone' do
    expect { ActiveModel::Type.lookup(:uuid) }.to raise_error(ArgumentError)
  end
end
