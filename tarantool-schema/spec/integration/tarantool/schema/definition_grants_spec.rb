# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Definition, :integration do
  describe '#apply with grants' do
    let(:client) { Tarantool::Client.new(ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301')) }

    let(:definition) do
      declared = codes_declaration

      described_class.new do
        ensure_space(:schema_codes, **declared)
        grant(:schema_app, %i[read write], on: :schema_codes)
        grant(:schema_reader, :read, on: :schema_codes)
      end
    end

    let(:cleanup_lua) do
      <<~LUA
        if box.space.schema_codes then box.space.schema_codes:drop() end
        if box.schema.user.exists('schema_app') then box.schema.user.drop('schema_app') end
        if box.schema.role.exists('schema_reader') then box.schema.role.drop('schema_reader') end
      LUA
    end

    def info(name) = client.eval('return box.schema.user.info(...)', [name]).first.select { |row| row[1] == 'space' }

    before do
      client.eval(cleanup_lua)
      client.eval("box.schema.user.create('schema_app', {password = 'x'}) box.schema.role.create('schema_reader')")
    end

    after do
      client.eval(cleanup_lua)
    ensure
      client.close
    end

    it 'grants to a user and a role after creating the space, then has nothing to do' do
      expect(definition.apply(client)).to eq(['space schema_codes', 'index schema_codes.primary',
                                              'index schema_codes.by_code',
                                              'grant schema_app read,write on schema_codes',
                                              'grant schema_reader read on schema_codes'])
      expect(info('schema_app')).to eq([['read,write', 'space', 'schema_codes']])
      expect(definition.apply(client)).to eq([])
    end

    it 'completes a partial grant and keeps extra privileges' do
      codes_definition(:schema_codes).apply(client)
      client.eval("box.schema.user.grant('schema_app', 'read,alter', 'space', 'schema_codes')")

      expect(definition.apply(client)).to eq(['grant schema_app write on schema_codes',
                                              'grant schema_reader read on schema_codes'])
      expect(info('schema_app')).to eq([['read,write,alter', 'space', 'schema_codes']])
    end

    it 'fails before creating anything when a grantee does not exist' do
      client.eval("box.schema.user.drop('schema_app')")

      expect { definition.apply(client) }
        .to raise_error(Tarantool::Schema::MismatchError, /grant schema_app: no such user or role/)
      expect(client.eval('return box.space.schema_codes ~= nil').first).to be(false)
    end

    it 'reads the grants back with from_live' do
      definition.apply(client)

      expect(described_class.from_live(client, only: [:schema_codes]).grants).to eq(definition.grants)
    end
  end
end
