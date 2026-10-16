box.cfg{memtx_dir = '/tmp', wal_dir = '/tmp', memtx_use_mvcc_engine = true}

box.once('bootstrap', function()
    box.schema.user.create('app', {password = 'secret'})
    box.schema.user.grant('app', 'read,write,execute', 'universe')

    local users = box.schema.space.create('users', {format = {
        {name = 'id', type = 'unsigned'},
        {name = 'email', type = 'string'},
        {name = 'age', type = 'unsigned'},
    }})
    users:create_index('primary', {parts = {'id'}})
    users:create_index('email', {parts = {'email'}})
    users:create_index('age', {parts = {'age'}, unique = false})

    box.schema.sequence.create('accounts_id')
    local accounts = box.schema.space.create('accounts', {format = {
        {name = 'id', type = 'unsigned'},
        {name = 'email', type = 'string'},
        {name = 'balance', type = 'decimal', is_nullable = true},
        {name = 'token', type = 'uuid', is_nullable = true},
        {name = 'created_at', type = 'datetime', is_nullable = true},
        {name = 'period', type = 'interval', is_nullable = true},
        {name = 'avatar', type = 'varbinary', is_nullable = true},
        {name = 'tags', type = 'any', is_nullable = true},
    }})
    accounts:create_index('primary', {parts = {'id'}, sequence = 'accounts_id'})
    accounts:create_index('email', {parts = {'email'}})
end)

-- Listen only after bootstrap so the healthcheck never sees a server without the app user.
box.cfg{listen = 3301}
