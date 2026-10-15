# frozen_string_literal: true

RSpec.describe Tarantool::Client, :integration do
  subject(:client) { described_class.new(ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301')) }

  before do
    client.execute('DROP TABLE IF EXISTS "sql_items"')
    client.execute('CREATE TABLE "sql_items" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "name" STRING NOT NULL)')
  end

  after do
    client.execute('DROP TABLE IF EXISTS "sql_items"')
    client.close
  end

  it 'reports the row count and generated ids of an insert' do
    result = client.execute('INSERT INTO "sql_items" ("name") VALUES (?), (?)', %w[a b])

    expect(result).to have_attributes(rows: [], row_count: 2, autoincrement_ids: [1, 2])
  end

  it 'returns rows and column names of a query' do
    client.execute(%q(INSERT INTO "sql_items" ("name") VALUES ('a')))
    result = client.execute('SELECT "id", "name" FROM "sql_items" WHERE "id" = ?', [1])

    expect(result).to have_attributes(rows: [[1, 'a']], columns: %w[id name], row_count: nil)
  end

  it 'binds named parameters' do
    client.execute(%q(INSERT INTO "sql_items" ("name") VALUES ('a')))

    expect(client.execute('SELECT "name" FROM "sql_items" WHERE "id" = :id', [{ ':id' => 1 }]).rows).to eq([['a']])
  end

  it 'executes a prepared statement until it is closed' do
    client.execute(%q(INSERT INTO "sql_items" ("name") VALUES ('a')))
    statement = client.prepare('SELECT "name" FROM "sql_items" WHERE "id" = ?')

    expect(statement.execute([1]).rows).to eq([['a']])
    statement.close
    expect { statement.execute([1]) }.to raise_error(Tarantool::ServerError) { |error| expect(error.code).to eq(211) }
  end

  it 'raises ServerError for invalid SQL' do
    expect { client.execute('SELEKT 1') }
      .to raise_error(Tarantool::ServerError) { |error| expect(error.code).to eq(184) }
  end
end
