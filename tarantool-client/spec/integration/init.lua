box.cfg{listen = 3301, memtx_use_mvcc_engine = true}

box.once('bootstrap', function()
    box.schema.user.create('app', {password = 'secret'})
    box.schema.user.grant('app', 'super')

    local users = box.schema.space.create('users', {
        format = {
            {name = 'id', type = 'unsigned'},
            {name = 'email', type = 'string'},
            {name = 'visits', type = 'unsigned'},
        },
    })
    users:create_index('primary', {parts = {'id'}})
    users:create_index('email', {parts = {'email'}, unique = true})
end)

function echo(...)
    return ...
end
