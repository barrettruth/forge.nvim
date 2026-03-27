local M = {}

function M.check()
  vim.health.start('forge.nvim')

  if vim.fn.executable('git') == 1 then
    vim.health.ok('git found')
  else
    vim.health.error('git not found')
  end

  local clis = {
    { 'gh', 'GitHub' },
    { 'glab', 'GitLab' },
    { 'tea', 'Codeberg/Gitea/Forgejo' },
  }
  for _, cli in ipairs(clis) do
    if vim.fn.executable(cli[1]) == 1 then
      vim.health.ok(cli[1] .. ' found (' .. cli[2] .. ')')
    else
      vim.health.info(cli[1] .. ' not found (' .. cli[2] .. ' support disabled)')
    end
  end

  local has_fzf = pcall(require, 'fzf-lua')
  if has_fzf then
    vim.health.ok('fzf-lua found')
  else
    vim.health.error('fzf-lua not found (required)')
  end

  local has_diffs = pcall(require, 'diffs')
  if has_diffs then
    vim.health.ok('diffs.nvim found (review mode available)')
  else
    vim.health.info('diffs.nvim not found (review mode disabled)')
  end

  local has_fugitive = vim.fn.exists(':Git') == 2
  if has_fugitive then
    vim.health.ok('vim-fugitive found (fugitive keymaps available)')
  else
    vim.health.info('vim-fugitive not found (fugitive keymaps disabled)')
  end
end

return M
