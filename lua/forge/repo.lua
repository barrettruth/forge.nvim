local M = {}

local detect_mod = require('forge.detect')
local scope_mod = require('forge.scope')

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

---@return string?
local function git_root()
  if type(detect_mod.git_root) == 'function' then
    return detect_mod.git_root()
  end
  return fn_system_text('git rev-parse --show-toplevel')
end

---@param range? { start_line: integer, end_line: integer }
---@return string
function M.file_loc(range)
  local root = git_root()
  if not root then
    return vim.fn.expand('%:t')
  end
  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name == '' or buf_name:match('^%w[%w+.-]*://') then
    return ''
  end
  local root_prefix = vim.fs.normalize(root) .. '/'
  local path = vim.fs.normalize(buf_name)
  if path:sub(1, #root_prefix) ~= root_prefix then
    return ''
  end
  local file = path:sub(#root_prefix + 1)
  if type(range) == 'table' and range.start_line and range.end_line then
    local s = range.start_line
    local e = range.end_line
    if s > e then
      s, e = e, s
    end
    if s == e then
      return ('%s:%d'):format(file, s)
    end
    return ('%s:%d-%d'):format(file, s, e)
  end
  local mode = vim.fn.mode()
  if mode:match('[vV]') or mode == '\22' then
    local s = vim.fn.line('v')
    local e = vim.fn.line('.')
    if s > e then
      s, e = e, s
    end
    if s == e then
      return ('%s:%d'):format(file, s)
    end
    return ('%s:%d-%d'):format(file, s, e)
  end
  return file
end

---@param scope? forge.Scope
---@return string
function M.remote_web_url(scope)
  if scope then
    return scope_mod.web_url(scope)
  end
  if not git_root() then
    return ''
  end
  local remote = fn_system_text('git remote get-url origin')
  if not remote then
    return ''
  end
  remote = remote:gsub('%.git$', '')
  remote = remote:gsub('^ssh://git@', 'https://')
  remote = remote:gsub('^git@([^:]+):', 'https://%1/')
  return remote
end

---@param name forge.ScopeKind
---@param url string
---@return forge.Scope?
function M.scope_from_url(name, url)
  return scope_mod.from_url(name, url)
end

---@param scope forge.Scope?
---@return string?
function M.scope_repo_arg(scope)
  return scope_mod.repo_arg(scope)
end

---@param scope forge.Scope?
---@return string
function M.scope_key(scope)
  return scope_mod.key(scope)
end

---@param name? forge.ScopeKind
---@return forge.Scope?
function M.current_scope(name)
  local url = M.remote_web_url()
  if url == '' then
    return nil
  end
  local forge_name = name
  if not forge_name then
    local f = detect_mod.detect()
    forge_name = f and f.name or nil
  end
  if not forge_name then
    return nil
  end
  return scope_mod.from_url(forge_name, url)
end

---@param scope forge.Scope?
---@return string?
function M.remote_name(scope)
  return scope_mod.remote_name(scope)
end

---@param scope forge.Scope?
---@param branch string
---@return string?
function M.remote_ref(scope, branch)
  return scope_mod.remote_ref(scope, branch)
end

return M
