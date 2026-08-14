local M = {}

function M.check()
  vim.health.start('forge.nvim')

  if vim.fn.has('nvim-0.11') == 1 then
    vim.health.ok('Neovim ' .. tostring(vim.version()))
  else
    vim.health.error('Neovim 0.11 or newer is required')
  end

  if vim.fn.executable('gh') == 0 then
    vim.health.error('gh not found', 'Install the GitHub CLI: https://cli.github.com')
    return
  end

  local version = vim.system({ 'gh', '--version' }, { text = true }):wait()
  vim.health.ok(vim.split(vim.trim(version.stdout), '\n')[1])

  local auth = vim.system({ 'gh', 'auth', 'status' }, { text = true }):wait()
  if auth.code == 0 then
    vim.health.ok('gh is authenticated')
  else
    vim.health.error('gh is not authenticated', 'Run: gh auth login')
  end
end

return M
