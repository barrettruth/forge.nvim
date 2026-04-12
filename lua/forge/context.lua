local M = {}

local providers = {}

local function git_output(cmd)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return vim.trim(result.stdout or '')
end

local function has_file_buffer()
  local buf_name = vim.api.nvim_buf_get_name(0)
  return buf_name ~= ''
    and not buf_name:match('^%w[%w+.-]*://')
    and not buf_name:match('^fugitive://')
    and not buf_name:match('^term://')
    and not buf_name:match('^diffs://')
end

local function in_repo_file(root)
  if not has_file_buffer() then
    return false
  end
  local buf_name = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  local prefix = vim.fs.normalize(root) .. '/'
  return buf_name:sub(1, #prefix) == prefix
end

providers.current = function()
  local root = git_output({ 'git', 'rev-parse', '--show-toplevel' })
  if not root then
    return nil, 'not a git repository'
  end

  local forge_mod = require('forge')
  local has_file = in_repo_file(root)

  return {
    id = 'current',
    root = root,
    branch = git_output({ 'git', 'branch', '--show-current' }) or '',
    head = git_output({ 'git', 'rev-parse', 'HEAD' }) or '',
    forge = forge_mod.detect(),
    has_file = has_file,
    loc = has_file and forge_mod.file_loc() or nil,
  }
end

function M.register(name, provider)
  providers[name] = provider
end

function M.get(name)
  return providers[name]
end

function M.resolve(name)
  local cfg = require('forge').config()
  local id = name or rawget(cfg, 'context') or 'current'
  local contexts = rawget(cfg, 'contexts') or {}

  if contexts[id] == false then
    return nil, 'disabled context: ' .. id
  end

  local provider = providers[id]
  if not provider then
    return nil, 'unknown context: ' .. id
  end

  local ctx, err = provider()
  if not ctx then
    return nil, err
  end

  if not ctx.id then
    ctx.id = id
  end

  return ctx
end

return M
