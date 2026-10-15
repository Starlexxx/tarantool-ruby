rawset(_G, 'vshard', require('vshard'))

local uri = 'storage:secret@127.0.0.1:3301'
local cfg = {
    bucket_count = 30,
    sharding = {
        ['aaaaaaaa-0000-4000-a000-000000000000'] = {
            replicas = {
                ['aaaaaaaa-0000-4000-a000-000000000001'] = { uri = uri, name = 'storage', master = true },
            },
        },
    },
    listen = 3301,
}

vshard.storage.cfg(cfg, 'aaaaaaaa-0000-4000-a000-000000000001')

box.once('crud-schema', function()
    box.schema.user.create('storage', { password = 'secret', if_not_exists = true })
    box.schema.user.grant('storage', 'super', nil, nil, { if_not_exists = true })
    box.schema.user.create('app', { password = 'secret', if_not_exists = true })
    box.schema.user.grant('app', 'super', nil, nil, { if_not_exists = true })

    local customers = box.schema.space.create('customers', {
        format = {
            { name = 'id', type = 'unsigned' },
            { name = 'bucket_id', type = 'unsigned' },
            { name = 'name', type = 'string' },
            { name = 'age', type = 'number' },
        },
        if_not_exists = true,
    })
    customers:create_index('primary', { parts = { 'id' }, if_not_exists = true })
    customers:create_index('bucket_id', { parts = { 'bucket_id' }, unique = false, if_not_exists = true })
    customers:create_index('age_index', { parts = { 'age' }, unique = false, if_not_exists = true })
end)

vshard.router.cfg(cfg)
vshard.router.bootstrap({ if_not_bootstrapped = true })

local crud = require('crud')
crud.init_storage()
crud.init_router()
crud.cfg({ stats = true })
