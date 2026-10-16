# frozen_string_literal: true

RSpec.describe Tarantool::Client::BatchDelete do
  subject(:batch_delete) do
    described_class.new(target, :users, [18], index: :age, iterator: :eq, batch_size: 2, timeout: nil)
  end

  let(:target) { target_class.new(rows, parts) }
  let(:rows) { [[1, 18], [2, 18], [3, 18], [4, 19]] }
  let(:parts) { [part(0)] }
  let(:target_class) do
    Class.new do
      attr_reader :rows, :calls

      def initialize(rows, parts)
        @rows = rows.dup
        @parts = parts
        @calls = []
      end

      def space_info(space, timeout: nil)
        @calls << [:space_info, timeout]
        primary = Tarantool::Client::IndexInfo.new(id: 0, name: 'primary', type: 'TREE', unique: true, parts: @parts)

        Tarantool::Client::SpaceInfo.new(id: 512, name: space.to_s, fields: [], indexes: { 'primary' => primary })
      end

      def select(_space, key, index:, iterator:, limit:, after:, timeout: nil)
        @calls << [:select, index, iterator, limit, after, timeout]
        found = @rows.select { |row| row[1] == key.first }.sort_by { |row| position(row) }
        found = skip_until_after(found, after) if after

        found.first(limit)
      end

      def delete(_space, key, timeout: nil)
        @calls << [:delete, key, timeout]

        @rows.delete(@rows.find { |row| row.values_at(*@parts.map(&:fieldno)) == key })
      end

      private

      def position(row)
        [row[1], *row.values_at(*@parts.map(&:fieldno))]
      end

      def skip_until_after(found, cursor)
        found.select { |row| (position(row) <=> position(cursor)).positive? }
      end
    end
  end

  def part(fieldno, path: nil)
    Tarantool::Client::IndexInfo::Part.new(fieldno:, name: nil, type: 'unsigned', is_nullable: false, path:)
  end

  def selects = target.calls.select { |call| call.first == :select }

  def build(**options)
    described_class.new(target, :users, [18], index: :age, iterator: :eq, batch_size: 2, timeout: nil, **options)
  end

  it 'deletes every matching tuple and returns the count' do
    expect(batch_delete.call).to eq(3)
    expect(target.rows).to eq([[4, 19]])
  end

  it 'pages with after: the last tuple of the previous batch' do
    batch_delete.call

    expect(selects.map { |call| call[4] }).to eq([nil, [2, 18]])
    expect(selects.first[1..3]).to eq([:age, :eq, 2])
  end

  it 'reads one extra empty batch when the count is a multiple of batch_size' do
    target.rows.delete([3, 18])

    expect(batch_delete.call).to eq(2)
    expect(selects.size).to eq(2)
    expect(target.rows).to eq([[4, 19]])
  end

  context 'with a composite primary key' do
    let(:rows) { [['b', 18, 1], ['a', 18, 2]] }
    let(:parts) { [part(2), part(0)] }

    it 'deletes by the primary key fields in part order' do
      batch_delete.call

      expect(target.calls.select { |call| call.first == :delete }.map { |call| call[1] }).to eq([[1, 'b'], [2, 'a']])
    end
  end

  it 'does not count a tuple that was already gone' do
    allow(target).to receive(:delete).and_return(nil)

    expect(batch_delete.call).to eq(0)
    expect(selects.size).to eq(2)
  end

  it 'rejects a batch_size that is not a positive Integer' do
    [0, -1, 1.5, nil].each do |batch_size|
      expect { build(batch_size:) }.to raise_error(ArgumentError, /batch_size/)
    end
  end

  context 'with a JSON path in the primary key' do
    let(:parts) { [part(0, path: '.id')] }

    it 'raises ArgumentError before deleting anything' do
      expect { batch_delete.call }.to raise_error(ArgumentError, /path/)
      expect(target.rows.size).to eq(4)
    end
  end

  it 'leaves each request on request_timeout without a timeout' do
    batch_delete.call

    expect(target.calls.map(&:last)).to all(be_nil)
  end

  context 'with a timeout' do
    let(:deadline) { Tarantool::Client::Transport::Deadline }

    it 'gives every request the remaining time' do
      allow(deadline).to receive(:now).and_return(0.0, 1.0, 2.0, 3.0, 3.0, 4.0, 4.0)

      build(timeout: 5).call

      expect(target.calls.map(&:last)).to eq([4.0, 3.0, 2.0, 2.0, 1.0, 1.0])
    end

    it 'raises TimeoutError carrying the count once the deadline passes' do
      allow(deadline).to receive(:now).and_return(0.0, 1.0, 1.0, 1.0, 9.0)
      message = 'delete_by did not finish within 5s'

      expect { build(timeout: 5).call }.to raise_error(Tarantool::TimeoutError, message) do |error|
        expect(error.deleted).to eq(1)
      end
    end
  end

  it 're-raises a failure mid-way as the same error with the count' do
    failure = Tarantool::ConnectionError.new('lost')
    calls = 0
    allow(target).to receive(:delete).and_wrap_original do |original, *args, **options|
      raise failure if (calls += 1) == 2

      original.call(*args, **options)
    end

    expect { batch_delete.call }.to raise_error(failure)
    expect(failure.deleted).to eq(1)
  end
end
