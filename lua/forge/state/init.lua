local M = {}

local cache_mod = require('forge.state.cache')
local detect_mod = require('forge.detect')
local resolve_mod = require('forge.resolve')
local scope_mod = require('forge.scope')
local target_mod = require('forge.target')

local repo_info_cache = cache_mod.new(30 * 60)
local pr_state_cache = cache_mod.new(60)
local list_cache = cache_mod.new(2 * 60)
local status_ttl = 30

---@type table<string, { value: forge.Status|false|nil, updated_at: integer?, inflight: boolean?, request_id: integer? }>
local status_cache = {}

local status_augroup

local git_root = detect_mod.git_root

---@param num string
---@param scope? forge.Scope
---@return string?
local function pr_state_key(num, scope)
  local root = git_root()
  return root and (root .. '|' .. scope_mod.key(scope) .. '|' .. num) or nil
end

local function emit_status_update()
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'ForgeStatusUpdate',
    modeline = false,
  })
end

---@param root string?
local function clear_status_cache(root)
  if root then
    status_cache[root] = nil
    return
  end
  status_cache = {}
end

local function setup_status_autocmds()
  if status_augroup then
    return
  end
  status_augroup = vim.api.nvim_create_augroup('forge_status', { clear = true })
  vim.api.nvim_create_autocmd({ 'DirChanged', 'FocusGained' }, {
    group = status_augroup,
    callback = function()
      clear_status_cache()
    end,
  })
end

---@param root string
---@param request_id integer
---@param value forge.Status?
local function set_status_value(root, request_id, value)
  local entry = status_cache[root]
  if not entry or entry.request_id ~= request_id then
    return
  end
  entry.inflight = false
  entry.updated_at = os.time()
  local previous = entry.value == false and nil or entry.value
  local next_value = value
  entry.value = value or false
  if not vim.deep_equal(previous, next_value) then
    emit_status_update()
  end
end

---@param root string
local function refresh_status(root)
  local entry = status_cache[root] or {}
  if entry.inflight then
    return
  end
  entry.inflight = true
  entry.request_id = (entry.request_id or 0) + 1
  status_cache[root] = entry
  ---@type integer
  local request_id = entry.request_id
  vim.schedule(function()
    local current = status_cache[root]
    if not current or current.request_id ~= request_id then
      return
    end
    local forge = detect_mod.detect_at_root(root)
    if not forge then
      local branch = target_mod.current_branch({ cwd = root })
      if branch then
        set_status_value(root, request_id, { branch = branch })
      else
        set_status_value(root, request_id, nil)
      end
      return
    end
    local head = resolve_mod.head(nil, {
      forge = forge,
      target_opts = {
        cwd = root,
      },
    })
    if not head then
      local branch = target_mod.current_branch({ cwd = root })
      if branch then
        set_status_value(root, request_id, { branch = branch })
      else
        set_status_value(root, request_id, nil)
      end
      return
    end
    local status = {
      branch = head.branch,
    }
    if head.scope then
      status.scope = head.scope
    end
    resolve_mod.current_pr_async({
      forge = forge,
      head_branch = head.branch,
      head_scope = head.scope,
      target_opts = {
        cwd = root,
      },
    }, function(pr)
      status.pr = pr
      set_status_value(root, request_id, status)
    end)
  end)
end

---@param f forge.Forge
---@param scope? forge.Scope
---@return forge.RepoInfo
function M.repo_info(f, scope)
  local root = git_root()
  local key = root and (root .. '|' .. scope_mod.key(scope)) or nil
  if key then
    local cached = repo_info_cache.get(key)
    if cached ~= nil then
      return cached
    end
  end
  local info = f:repo_info(scope)
  if key then
    repo_info_cache.set(key, info)
  end
  return info
end

---@param f forge.Forge
---@param num string
---@param scope? forge.Scope
---@return forge.PRState
function M.pr_state(f, num, scope)
  local key = pr_state_key(num, scope)
  if key then
    local cached = pr_state_cache.get(key)
    if cached ~= nil then
      return cached
    end
  end
  local state = f:pr_state(num, scope)
  if key then
    pr_state_cache.set(key, state)
  end
  return state
end

---@param num string
---@param state forge.PRState
---@param scope? forge.Scope
---@return forge.PRState
function M.set_pr_state(num, state, scope)
  local key = pr_state_key(num, scope)
  if key then
    pr_state_cache.set(key, state)
  end
  return state
end

---@param num? string
---@param scope? forge.Scope
function M.clear_pr_state(num, scope)
  local root = git_root()
  clear_status_cache(root)
  if not root then
    pr_state_cache.clear()
    return
  end
  if num ~= nil then
    local key = pr_state_key(num, scope)
    if key then
      pr_state_cache.clear(key)
      return
    end
    pr_state_cache.clear()
    return
  end
  if scope ~= nil then
    pr_state_cache.clear_prefix(root .. '|' .. scope_mod.key(scope) .. '|')
    return
  end
  pr_state_cache.clear()
end

---@param kind string
---@param state string
---@return string
function M.list_key(kind, state)
  local root = git_root() or ''
  return root .. ':' .. kind .. ':' .. state
end

---@param key string
---@return table[]?
function M.get_list(key)
  return list_cache.get(key)
end

---@param key string
---@param data table[]
function M.set_list(key, data)
  list_cache.set(key, data)
end

---@param key string?
function M.clear_list(key)
  list_cache.clear(key)
  local root = type(key) == 'string' and key:match('^(.-):') or git_root()
  clear_status_cache(root)
end

---@param kind string
function M.clear_list_kind(kind)
  local root = git_root() or ''
  list_cache.clear_prefix(root .. ':' .. kind .. ':')
  clear_status_cache(root ~= '' and root or nil)
end

function M.clear_cache()
  repo_info_cache.clear()
  pr_state_cache.clear()
  list_cache.clear()
  clear_status_cache()
end

---@return forge.Status?
function M.status()
  setup_status_autocmds()
  local root = git_root()
  if not root then
    return nil
  end
  local entry = status_cache[root]
  local stale = not entry or not entry.updated_at or entry.updated_at <= (os.time() - status_ttl)
  if stale then
    refresh_status(root)
    entry = status_cache[root]
  end
  if not entry or entry.value == false or entry.value == nil then
    return nil
  end
  local value = entry.value
  ---@cast value forge.Status
  return value
end

return M
