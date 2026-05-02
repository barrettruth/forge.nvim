local M = {}

local config_mod = require('forge.config')
local detect_mod = require('forge.detect')
local review_mod = require('forge.review')

local function codediff_status()
  if vim.fn.exists(':CodeDiff') ~= 2 then
    return false, false
  end
  local ok, installer = pcall(require, 'codediff.core.installer')
  if not ok then
    return true, true
  end
  local needs_update = type(installer.needs_update) == 'function' and installer.needs_update()
  return true, not needs_update
end

local review_integrations = {
  diffview = {
    available = function()
      return vim.fn.exists(':DiffviewOpen') == 2
    end,
    ok = 'diffview.nvim found (adapter=diffview available)',
    info = 'diffview.nvim not found (adapter=diffview unavailable)',
    warn = 'review.adapter=diffview but diffview.nvim is not available (:DiffviewOpen missing)',
  },
  diffs = {
    available = function()
      return vim.fn.exists(':Greview') == 2
    end,
    ok = 'diffs.nvim found (adapter=diffs available)',
    info = 'diffs.nvim not found (adapter=diffs unavailable)',
    warn = 'review.adapter=diffs but diffs.nvim is not available (:Greview missing)',
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
    { 'tea', 'Forgejo/Gitea/Codeberg' },
  }
  for _, cli in ipairs(clis) do
    if vim.fn.executable(cli[1]) == 1 then
      vim.health.ok(cli[1] .. ' found (' .. cli[2] .. ')')
    else
      vim.health.info(cli[1] .. ' not found (' .. cli[2] .. ' support disabled)')
    end
  end

  vim.health.start('Interactive picker UI')
  local picker = require('forge.picker')
  if picker.ui_available() then
    vim.health.ok(
      "fzf-lua found (require('forge').open() and require('forge.picker').pick() enabled)"
    )
  else
    vim.health.info(picker.unavailable_message())
  end

  vim.health.start('Tree-sitter')
  local has_yaml = pcall(vim.treesitter.language.inspect, 'yaml')
  if has_yaml then
    vim.health.ok('tree-sitter yaml parser found')
  else
    vim.health.error('tree-sitter yaml parser not found (required for YAML issue form templates)')
  end

  local configured_adapter = vim.trim((((config_mod.config() or {}).review or {}).adapter or ''))
  local review_names = {}
  for _, name in ipairs(review_mod.names()) do
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

  local has_codediff, codediff_ready = codediff_status()
  if has_codediff then
    if codediff_ready then
      vim.health.ok('codediff.nvim found (adapter=codediff available)')
    elseif configured_adapter == 'codediff' then
      vim.health.warn(
        'codediff.nvim found but libvscode-diff needs install/update (:CodeDiff install or first use)'
      )
    else
      vim.health.info('codediff.nvim found but libvscode-diff needs install/update')
    end
  elseif configured_adapter == 'codediff' then
    vim.health.warn('codediff.nvim not found (review.adapter=codediff unavailable)')
  else
    vim.health.info('codediff.nvim not found (adapter=codediff unavailable)')
  end

  if
    configured_adapter ~= ''
    and configured_adapter ~= 'codediff'
    and not review_integrations[configured_adapter]
  then
    if review_names[configured_adapter] then
      vim.health.ok('configured review adapter "' .. configured_adapter .. '" available')
    else
      vim.health.warn('configured review adapter "' .. configured_adapter .. '" is not registered')
    end
  end

  vim.health.start('Registered sources')
  for name, source in pairs(detect_mod.registered_sources()) do
    if name ~= 'github' and name ~= 'gitlab' and name ~= 'forgejo' then
      if vim.fn.executable(source.cli) == 1 then
        vim.health.ok(source.cli .. ' found (custom: ' .. name .. ')')
      else
        vim.health.warn(source.cli .. ' not found (custom: ' .. name .. ' disabled)')
      end
    end
  end
end

return M
