local log = require('forge.log')
local uri = require('forge.uri')
local view = require('forge.view')

local M = {}

--- ci.nvim, if it is there to be used.
---
--- An installed plugin is not a loaded one. Under `pack/*/opt` nothing is on
--- the runtimepath until |:packadd|, so requiring first would call an
--- installed ci.nvim missing merely because its own trigger had not fired.
--- The flag settles it either way: it lives in ci.nvim's plugin file, and with
--- the module loaded and the plugin not, `:CI` opens a buffer nothing fills.
--- @return table?
function M.available()
  if not vim.g.loaded_ci then
    pcall(vim.cmd.packadd, 'ci.nvim')
  end
  local ok, ci = pcall(require, 'ci')
  if not ok or not vim.g.loaded_ci then
    return nil
  end
  return ci
end

--- Hand this pull request to ci.nvim.
---
--- It goes over as its github.com URL, which is a target |:CI| already accepts,
--- so forge needs to know nothing about how ci.nvim addresses its own buffers.
--- ci.nvim's own "-" is pointed back here, so the way out of the checks is the
--- key that already means "out".
function M.checks()
  local u = view.current()
  if not u or u.collection ~= 'prs' or not u.number then
    local nouns = require('forge.backend').of(u and u.host).nouns.prs
    log.warn(('no %s here to show checks for'):format(nouns.one))
    return
  end

  local ci = M.available()
  if not ci then
    log.err('ci.nvim is not available')
    return
  end

  local from = uri.tostring(u)
  ci.run(view.field('url'))

  local buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(buf) ~= from then
    vim.b[buf].ci = vim.tbl_extend('force', vim.b[buf].ci or {}, { up = from })
  end
end

return M
