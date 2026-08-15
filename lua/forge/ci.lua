local log = require('forge.log')
local uri = require('forge.uri')
local view = require('forge.view')

local M = {}

--- ci.nvim, if it is there to be used.
---
--- An optional dependency. Forge delegates CI rather than drawing it, so the
--- honest thing when there is nothing to delegate to is to say so.
---
--- An installed plugin is not a loaded one. Under `pack/*/opt` nothing is on
--- the runtimepath until |:packadd|, so requiring first would call an
--- installed ci.nvim missing merely because its own trigger had not fired.
--- The flag is what settles it either way: it lives in ci.nvim's plugin file,
--- which is exactly what a handover needs, since with the module loaded and
--- the plugin not, `:CI` would open a buffer nothing ever fills.
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
--- The pull request goes over as its github.com URL, which is a target |:CI|
--- already accepts, so forge needs to know nothing about how ci.nvim addresses
--- its own buffers.
---
--- The checks replace this view rather than splitting beside it: they are the
--- same pull request seen differently, which is the relationship <CR> already
--- has with a list. ci.nvim's own "-" is pointed back here, so the way out is
--- the key that already means "out".
function M.checks()
  local u = view.current()
  if not u or u.collection ~= 'prs' or not u.number then
    log.warn('no pull request here to show checks for')
    return
  end

  local ci = M.available()
  if not ci then
    log.err('ci.nvim is not available')
    return
  end

  local from = uri.tostring(u)
  ci.run(uri.web(u))

  local buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(buf) ~= from then
    vim.b[buf].ci = vim.tbl_extend('force', vim.b[buf].ci or {}, { up = from })
  end
end

return M
