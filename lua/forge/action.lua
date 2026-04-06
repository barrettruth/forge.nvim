local M = {}

local actions = {}

actions.open = {
  label = 'open',
  fn = function(entry, opts)
    if not entry then
      return
    end

    local context = opts.context
    if type(context) == 'table' then
      context = context.id
    end

    require('forge.routes').open(entry.value, { context = context })
  end,
}

function M.register(name, action)
  if type(action) == 'function' then
    action = { fn = action }
  end
  actions[name] = action
end

function M.get(name)
  return actions[name]
end

function M.run(name, entry, opts)
  local action = actions[name]
  if not action then
    return false, 'unknown action: ' .. name
  end
  action.fn(entry, opts or {})
  return true
end

function M.bind(name, opts)
  local action = actions[name]
  if not action then
    return nil, 'unknown action: ' .. name
  end

  opts = opts or {}
  local close = rawget(opts, 'close')
  if close == nil then
    close = rawget(action, 'close')
  end

  return {
    name = opts.name or name,
    label = opts.label or action.label or name,
    close = close,
    fn = function(entry)
      M.run(name, entry, opts)
    end,
  }
end

return M
