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

  local forge_mod = require('forge')
  for name, source in pairs(forge_mod.registered_sources()) do
    if name ~= 'github' and name ~= 'gitlab' and name ~= 'codeberg' then
      if vim.fn.executable(source.cli) == 1 then
        vim.health.ok(source.cli .. ' found (custom: ' .. name .. ')')
      else
        vim.health.warn(source.cli .. ' not found (custom: ' .. name .. ' disabled)')
      end
    end
  end
end

return M
