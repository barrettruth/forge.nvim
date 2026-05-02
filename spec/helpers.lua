---@class forge.SpecPreloadEntry
---@field name string
---@field loader function?

---@class forge.SpecCommandResult
---@field code integer
---@field stdout string
---@field stderr string

---@alias forge.SpecSystemResponse forge.SpecCommandResult|fun(key: string, cmd: string[]): forge.SpecCommandResult

---@class forge.SpecSystemRouterOpts
---@field responses table<string, forge.SpecSystemResponse>?
---@field default forge.SpecCommandResult?
---@field calls string[]?

---@class forge.SpecWaitOpts
---@field timeout integer?
---@field interval integer?

local M = {}

---@param names string[]
---@return forge.SpecPreloadEntry[]
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

---@param captured forge.SpecPreloadEntry[]
function M.restore_preload(captured)
  for _, entry in ipairs(captured) do
    package.preload[entry.name] = entry.loader
  end
end

---@param names string[]
function M.clear_loaded(names)
  for _, name in ipairs(names) do
    package.loaded[name] = nil
  end
end

---@param actions table[]?
---@param name string
---@return table?
function M.action_by_name(actions, name)
  for _, def in ipairs(actions or {}) do
    if def.name == name then
      return def
    end
  end
end

---@param actions table[]?
---@param entry table?
---@return table<string, string?>
function M.action_labels(actions, entry)
  local labels = {}
  local ok, surface_policy = pcall(require, 'forge.surface.policy')
  for _, def in ipairs(actions or {}) do
    local label
    if ok and type(surface_policy.resolve_label) == 'function' then
      label = surface_policy.resolve_label(def, entry)
    else
      label = def.label
      if type(label) == 'function' then
        label = label(entry)
      end
    end
    labels[def.name] = label
  end
  return labels
end

---@param stdout string?
---@param code integer?
---@param stderr string?
---@return forge.SpecCommandResult
function M.command_result(stdout, code, stderr)
  return {
    code = code or 0,
    stdout = stdout or '',
    stderr = stderr or '',
  }
end

---@param opts forge.SpecSystemRouterOpts
---@return fun(cmd: string[], opts?: table, cb?: fun(result: forge.SpecCommandResult)): table
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

---@param predicate fun(): boolean?
---@param opts forge.SpecWaitOpts?
---@return boolean
function M.wait_for(predicate, opts)
  opts = opts or {}
  return vim.wait(opts.timeout or 50, predicate, opts.interval or 1)
end

---@param timeout integer?
---@return boolean
function M.pump(timeout)
  return vim.wait(timeout or 10)
end

return M
