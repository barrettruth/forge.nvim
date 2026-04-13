local M = {}

function M.capture_preload(names)
  local captured = {}
  for _, name in ipairs(names) do
    captured[#captured + 1] = {
      name = name,
      loader = package.preload[name],
    }
  end
  return captured
end

function M.restore_preload(captured)
  for _, entry in ipairs(captured) do
    package.preload[entry.name] = entry.loader
  end
end

function M.clear_loaded(names)
  for _, name in ipairs(names) do
    package.loaded[name] = nil
  end
end

function M.action_by_name(actions, name)
  for _, def in ipairs(actions or {}) do
    if def.name == name then
      return def
    end
  end
end

function M.action_labels(actions)
  local labels = {}
  for _, def in ipairs(actions or {}) do
    labels[def.name] = def.label
  end
  return labels
end

function M.command_result(stdout, code, stderr)
  return {
    code = code or 0,
    stdout = stdout or '',
    stderr = stderr or '',
  }
end

function M.system_router(opts)
  local responses = opts.responses or {}
  local default = vim.deepcopy(opts.default or M.command_result())
  local calls = opts.calls

  return function(cmd, _, cb)
    local key = table.concat(cmd, ' ')
    if calls then
      table.insert(calls, key)
    end

    local response = responses[key]
    local result
    if type(response) == 'function' then
      result = response(key, cmd)
    elseif response ~= nil then
      result = vim.deepcopy(response)
    else
      result = vim.deepcopy(default)
    end

    if cb then
      cb(result)
    end

    return {
      wait = function()
        return result
      end,
    }
  end
end

return M
