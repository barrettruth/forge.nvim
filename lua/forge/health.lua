local M = {}

function M.check()
  vim.health.start('forge.nvim')

  if vim.fn.has('nvim-0.12') == 1 then
    vim.health.ok('Neovim ' .. tostring(vim.version()))
  else
    vim.health.error('Neovim 0.12 or newer is required')
  end

  if vim.fn.executable('gh') == 0 then
    vim.health.error('gh not found', 'Install the GitHub CLI: https://cli.github.com')
  else
    local version = vim.system({ 'gh', '--version' }, { text = true }):wait()
    vim.health.ok(vim.split(vim.trim(version.stdout), '\n')[1])

    local auth = vim.system({ 'gh', 'auth', 'status' }, { text = true }):wait()
    if auth.code == 0 then
      vim.health.ok('gh is authenticated')
    else
      vim.health.error('gh is not authenticated', 'Run: gh auth login')
    end
  end

  if vim.fn.executable('glab') == 0 then
    vim.health.warn(
      'glab not found, so no gitlab project can be opened',
      'Needed for gitlab only. Install it from https://gitlab.com/gitlab-org/cli'
    )
  else
    local version = vim.system({ 'glab', '--version' }, { text = true }):wait()
    vim.health.ok(vim.split(vim.trim(version.stdout), '\n')[1])

    local auth = vim.system({ 'glab', 'auth', 'status' }, { text = true }):wait()
    if auth.code == 0 then
      vim.health.ok('glab is authenticated')
    else
      vim.health.warn('glab is not authenticated', 'Run: glab auth login')
    end
  end

  if require('forge.ci').available() then
    vim.health.ok('ci.nvim loaded, so dc can show a pull request its checks')
  else
    vim.health.warn(
      'ci.nvim not available, so dc has nothing to show checks with',
      'Optional. Install it from https://forge.barrettruth.com/barrettruth/ci.nvim'
    )
  end

  if require('forge.diff').available() then
    vim.health.ok('diffs.nvim loaded, so dd can show a pull request its diff')
  else
    vim.health.warn(
      'diffs.nvim not available, so dd has nothing to show a diff with',
      'Optional. Install it from https://forge.barrettruth.com/barrettruth/diffs.nvim'
    )
  end

  if require('forge.commits').available() then
    vim.health.ok('vim-fugitive loaded, so dl can show a pull request its commits')
  else
    vim.health.warn(
      'vim-fugitive not available, so dl has nothing to show commits with',
      'Optional. Install it from https://github.com/tpope/vim-fugitive'
    )
  end
end

return M
