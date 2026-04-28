local M = {}

local config_mod = require('forge.config')

---@type table<string, forge.Forge>
local registered_sources = {}

---@type table<string, { name: string, source: forge.Forge }>
local forge_cache = {}

---@type table<string, string>
local root_cache = {}

local builtin_hosts = {
  github = { 'github' },
  gitlab = { 'gitlab' },
  codeberg = { 'codeberg', 'gitea', 'forgejo' },
}

---@param cmd string
---@return string?
local function fn_system_text(cmd)
  local text = vim.trim(vim.fn.system(cmd))
  if vim.v.shell_error ~= 0 and (text == '' or text:match('^fatal:') or text:match('^error:')) then
    return nil
  end
  if text == '' then
    return nil
  end
  return text
end

---@param cmd string[]
---@return string?
local function system_text(cmd)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  local text = vim.trim(result.stdout or '')
  if text == '' then
    return nil
  end
  return text
end

---@param name string
---@param source forge.Forge
function M.register(name, source)
  registered_sources[name] = source
end

---@return table<string, forge.Forge>
function M.registered_sources()
  return registered_sources
end

---@param name string
---@return forge.Forge?
local function resolve_source(name)
  if registered_sources[name] then
    return registered_sources[name]
  end
  local ok, mod = pcall(require, 'forge.backends.' .. name)
  if ok then
    return mod
  end
  return nil
end

---@param root string
---@return forge.Forge?
local function cached_source(root)
  local cached = forge_cache[root]
  if type(cached) ~= 'table' or type(cached.name) ~= 'string' or type(cached.source) ~= 'table' then
    return nil
  end
  local registered = registered_sources[cached.name]
  if registered then
    if registered == cached.source then
      return cached.source
    end
    forge_cache[root] = nil
    return nil
  end
  if package.loaded['forge.backends.' .. cached.name] == cached.source then
    return cached.source
  end
  forge_cache[root] = nil
  return nil
end

---@param remote string
---@return string? forge_name
local function detect_from_remote(remote)
  local cfg = config_mod.config().sources

  for name, opts in pairs(cfg) do
    for _, host in ipairs(opts.hosts or {}) do
      if remote:find(host, 1, true) then
        return name
      end
    end
  end

  for name, patterns in pairs(builtin_hosts) do
    for _, pattern in ipairs(patterns) do
      if remote:find(pattern, 1, true) then
        return name
      end
    end
  end

  return nil
end

---@return string?
function M.git_root()
  local cwd = vim.fn.getcwd()
  if root_cache[cwd] then
    return root_cache[cwd]
  end
  local root = fn_system_text('git rev-parse --show-toplevel')
  if not root then
    return nil
  end
  root_cache[cwd] = root
  return root
end

---@param root string
---@return forge.Forge?
function M.detect_at_root(root)
  local log = require('forge.logger')
  local cached = cached_source(root)
  if cached then
    return cached
  end
  local remote = system_text({ 'git', '-C', root, 'remote', 'get-url', 'origin' })
  if not remote then
    log.debug('detect: no origin remote')
    return nil
  end
  local name = detect_from_remote(remote)
  if not name then
    log.debug('detect: no forge matched remote ' .. remote)
    return nil
  end
  local source = resolve_source(name)
  if not source then
    log.debug('detect: failed to load source module ' .. name)
    return nil
  end
  if vim.fn.executable(source.cli) ~= 1 then
    log.debug('detect: CLI ' .. source.cli .. ' not found')
    return nil
  end
  forge_cache[root] = {
    name = name,
    source = source,
  }
  return source
end

---@return forge.Forge?
function M.detect()
  local log = require('forge.logger')
  local root = M.git_root()
  if not root then
    log.debug('detect: not a git repository')
    return nil
  end
  local cached = cached_source(root)
  if cached then
    return cached
  end
  local remote = fn_system_text('git remote get-url origin')
  if not remote then
    log.debug('detect: no origin remote')
    return nil
  end
  local name = detect_from_remote(remote)
  if not name then
    log.debug('detect: no forge matched remote ' .. remote)
    return nil
  end
  local source = resolve_source(name)
  if not source then
    log.debug('detect: failed to load source module ' .. name)
    return nil
  end
  if vim.fn.executable(source.cli) ~= 1 then
    log.debug('detect: CLI ' .. source.cli .. ' not found')
    return nil
  end
  forge_cache[root] = {
    name = name,
    source = source,
  }
  return source
end

function M.clear_cache()
  forge_cache = {}
  root_cache = {}
end

function M.forge_name()
  local ok, forge = pcall(require, 'forge')
  if not ok or type(forge) ~= 'table' or type(forge.detect) ~= 'function' then
    return nil
  end
  local detected = forge.detect()
  if type(detected) ~= 'table' or type(detected.name) ~= 'string' or detected.name == '' then
    return nil
  end
  return detected.name
end

return M
