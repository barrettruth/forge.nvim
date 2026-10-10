local M = {}

local message = table.concat({
  '[forge.nvim] This repository will be removed from GitHub on October 31, 2026.',
  'Install from Forgejo: https://forge.barrettruth.com/barrettruth/forge.nvim.',
  'See :help forge-migration.',
}, ' ')

---@param origin unknown
---@return boolean
function M.is_github_origin(origin)
  if type(origin) ~= 'string' then
    return false
  end

  origin = origin:gsub('/+$', ''):gsub('%.git$', '')

  return origin == 'https://github.com/barrettruth/forge.nvim'
    or origin == 'http://github.com/barrettruth/forge.nvim'
    or origin == 'git://github.com/barrettruth/forge.nvim'
    or origin == 'ssh://git@github.com/barrettruth/forge.nvim'
    or origin == 'git@github.com:barrettruth/forge.nvim'
end

---@return string
function M.plugin_root()
  local source = debug.getinfo(1, 'S').source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
end

--- @param root string
--- @param on_origin fun(origin: string)
function M.origin(root, on_origin)
  if vim.fn.executable('git') ~= 1 then
    return
  end

  pcall(
    vim.system,
    { 'git', '-C', root, 'config', '--get', 'remote.origin.url' },
    { text = true },
    function(result)
      if result.code ~= 0 or not result.stdout then
        return
      end

      vim.schedule(function()
        on_origin(vim.trim(result.stdout))
      end)
    end
  )
end

--- @param root? string
function M.warn_if_github_source(root)
  M.origin(root or M.plugin_root(), function(origin)
    if M.is_github_origin(origin) then
      pcall(vim.notify_once, message, vim.log.levels.WARN)
    end
  end)
end

return M
