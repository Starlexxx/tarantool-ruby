# frozen_string_literal: true

# In-memory storage contract for model unit specs. The first index is the primary one; index values must not
# be nil (they are sorted). A nil single-field primary key gets the next id, like a sequence.
class MemoryStorage
  USERS = { fields: %i[id email age], indexes: { primary: %i[id], email: %i[email], age: %i[age] } }.freeze
  DESCENDING = %i[le lt].freeze

  Space = Struct.new(:fields, :indexes, :rows) do
    def primary = indexes.values.first

    def key_of(attributes, index = primary) = index.map { |name| attributes[name] }

    def order_of(attributes, index) = key_of(attributes, index) + key_of(attributes)

    def row(attributes)
      Tarantool::Model::Row.new(attributes: attributes.dup, tuple: fields.map { |name| attributes[name] })
    end
  end

  def initialize(spaces)
    @spaces = spaces.to_h do |name, schema|
      [name.to_s, Space.new(schema.fetch(:fields), schema.fetch(:indexes), {})]
    end
  end

  def verify(*, **) = nil

  def get(space, key)
    found = space(space).rows[key]

    found && space(space).row(found)
  end

  def insert(space, attributes)
    table = space(space)
    record = table.fields.to_h { |name| [name, attributes[name]] }
    fill_sequence(table, record)
    key = table.key_of(record)
    raise Tarantool::Model::RecordNotUnique, 'Duplicate key exists' if table.rows.key?(key)

    table.rows[key] = record

    table.row(record)
  end

  def update(space, key, operations)
    found = space(space).rows[key]
    return unless found

    operations.each { |operator, name, value| found[name.to_sym] = apply(operator, found[name.to_sym], value) }

    space(space).row(found)
  end

  def delete(space, key)
    found = space(space).rows.delete(key)

    found && space(space).row(found)
  end

  def select(space, index:, key:, iterator:, limit:, after:)
    table = space(space)
    rows = matching(table, index, key, iterator)
    rows = past(table, rows, index, iterator, after) if after
    rows = rows.first(limit) if limit

    rows.map { |attributes| table.row(attributes) }
  end

  def count(space, index:, key:, iterator:) = matching(space(space), index, key, iterator).size

  private

  def space(name) = @spaces.fetch(name.to_s)

  def index_fields(table, index) = index ? table.indexes.fetch(index.to_sym) : table.primary

  def matching(table, index, key, iterator)
    fields = index_fields(table, index)
    rows = table.rows.values.sort_by { |attributes| table.order_of(attributes, fields) }
    rows.reverse! if DESCENDING.include?(iterator)

    rows.select { |attributes| matches?(table.key_of(attributes, fields).first(key.size) <=> key, key, iterator) }
  end

  def matches?(comparison, key, iterator)
    return true if key.empty? || iterator == :all

    { eq: comparison.zero?, ge: comparison >= 0, gt: comparison.positive?, le: comparison <= 0,
      lt: comparison.negative? }.fetch(iterator)
  end

  def past(table, rows, index, iterator, tuple)
    fields = index_fields(table, index)
    position = table.order_of(table.fields.zip(tuple).to_h, fields)
    sign = DESCENDING.include?(iterator) ? -1 : 1

    rows.select { |attributes| (table.order_of(attributes, fields) <=> position) * sign == 1 }
  end

  def fill_sequence(table, record)
    name, = table.primary
    return unless table.primary.size == 1 && record[name].nil?

    record[name] = (table.rows.keys.map(&:first).max || 0) + 1
  end

  def apply(operator, current, value)
    case operator
    when '=' then value
    when '+' then current + value
    when '-' then current - value
    else raise ArgumentError, "unsupported operator #{operator}"
    end
  end
end
