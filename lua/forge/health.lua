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

  local ok = pcall(require, 'fzf-lua')
  if ok then
    vim.health.ok('fzf-lua found (interactive picker UI enabled)')
  else
    vim.health.warn(
      'fzf-lua not found (interactive picker UI disabled; direct :Forge commands still available)'
    )
  end

  local has_yaml = pcall(vim.treesitter.language.inspect, 'yaml')
  if has_yaml then
    vim.health.ok('tree-sitter yaml parser found')
  else
    vim.health.error('tree-sitter yaml parser not found (required for YAML issue form templates)')
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
