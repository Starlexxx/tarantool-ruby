# frozen_string_literal: true

RSpec.describe Tarantool::Schema::Definition, :integration do
  describe '#apply with minimal privileges' do
    let(:uri) { ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301') }
    let(:admin) { Tarantool::Client.new(uri) }

    let(:definition) do
      declared = codes_declaration

      described_class.new do
        ensure_space(:schema_codes, **declared)
        grant(:schema_app, :read, on: :schema_codes)
      end
    end

    # Universe privileges can be granted only by admin on 2.11, hence box.session.su. 3.x moved eval to lua_eval.
    let(:grant_lua) do
      <<~LUA
        local user, password = ...
        box.schema.user.create(user, {password = password})
        local function grant(...) box.session.su('admin', box.schema.user.grant, user, ...) end
        if tonumber(_TARANTOOL:match('^(%d+)')) >= 3 then grant('execute', 'lua_eval') else grant('execute', 'universe') end
        grant('create', 'space')
        grant('create', 'sequence')
        for _, name in ipairs({'_space', '_index', '_sequence', '_space_sequence', '_priv'}) do grant('read,write', 'space', name) end
        grant('read', 'space', '_user')
        box.schema.user.create('schema_app', {password = 'x'})
      LUA
    end

    let(:cleanup_lua) do
      <<~LUA
        if box.space.schema_codes then box.space.schema_codes:drop() end
        if box.sequence.schema_codes_seq then box.sequence.schema_codes_seq:drop() end
        if box.schema.user.exists('schema_deployer') then box.schema.user.drop('schema_deployer') end
        if box.schema.user.exists('schema_app') then box.schema.user.drop('schema_app') end
      LUA
    end

    before do
      admin.eval(cleanup_lua)
      admin.eval(grant_lua, %w[schema_deployer schema_pw])
    end

    after do
      admin.eval(cleanup_lua)
    ensure
      admin.close
    end

    it 'creates a space with a sequence and grants on it' do
      deployer = Tarantool::Client.new(uri.sub('app:secret', 'schema_deployer:schema_pw'))

      expect(definition.apply(deployer)).to eq(['space schema_codes', 'index schema_codes.primary',
                                                'index schema_codes.by_code', 'grant schema_app read on schema_codes'])
      expect(definition.plan(deployer)).to eq([])
    ensure
      deployer&.close
    end
  end
end
