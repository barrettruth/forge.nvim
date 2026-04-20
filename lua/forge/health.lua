local M = {}

local review_integrations = {
  diffview = {
    available = function()
      return vim.fn.exists(':DiffviewOpen') == 2
    end,
    ok = 'diffview.nvim found (adapter=diffview available)',
    info = 'diffview.nvim not found (adapter=diffview unavailable)',
    warn = 'review.adapter=diffview but diffview.nvim is not available (:DiffviewOpen missing)',
  },
}

function M.check()
  vim.health.start('Core tools')

  if vim.fn.executable('git') == 1 then
    vim.health.ok('git found')
  else
    vim.health.error('git not found')
  end

  vim.health.start('Forge CLIs')
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

  vim.health.start('Interactive picker UI')
  local ok = pcall(require, 'fzf-lua')
  if ok then
    vim.health.ok('fzf-lua found (interactive picker UI enabled)')
  else
    vim.health.info(
      'fzf-lua not found (interactive picker UI disabled; direct :Forge commands still available)'
    )
  end

  vim.health.start('Tree-sitter')
  local has_yaml = pcall(vim.treesitter.language.inspect, 'yaml')
  if has_yaml then
    vim.health.ok('tree-sitter yaml parser found')
  else
    vim.health.error('tree-sitter yaml parser not found (required for YAML issue form templates)')
  end

  local forge_mod = require('forge')
  local configured_adapter = vim.trim((((forge_mod.config() or {}).review or {}).adapter or ''))
  local review_names = {}
  for _, name in ipairs((forge_mod.review_adapter_names and forge_mod.review_adapter_names()) or {}) do
    review_names[name] = true
  end

  vim.health.start('Review adapters')
  for name, integration in pairs(review_integrations) do
    local available = integration.available()
    if configured_adapter == name then
      if available then
        vim.health.ok(integration.ok)
      else
        vim.health.warn(integration.warn)
      end
    elseif available then
      vim.health.ok(integration.ok)
    else
      vim.health.info(integration.info)
    end
  end
  if configured_adapter ~= '' and not review_integrations[configured_adapter] then
    if review_names[configured_adapter] then
      vim.health.ok('configured review adapter "' .. configured_adapter .. '" available')
    else
      vim.health.warn('configured review adapter "' .. configured_adapter .. '" is not registered')
    end
  end

  vim.health.start('Registered sources')
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
