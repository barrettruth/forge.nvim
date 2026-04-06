local M = {}

local clients = {}

clients.picker = function(opts)
  require('forge.picker').pick({
    prompt = opts.prompt,
    entries = opts.entries,
    actions = {
      {
        name = 'default',
        label = 'open',
        fn = function(entry)
          if opts.on_select then
            opts.on_select(entry)
          end
        end,
      },
    },
    picker_name = '_menu',
  })
end

function M.register(name, client)
  clients[name] = client
end

function M.get(name)
  return clients[name]
end

function M.open_root(name, opts)
  local client = clients[name]
  if not client then
    return false, 'unknown client: ' .. name
  end
  client(opts)
  return true
end

return M
