local log = require('forge.log')
local uri = require('forge.uri')
local view = require('forge.view')

local M = {}

--- ci.nvim, if it is there to be used.
---
--- An optional dependency. Forge delegates CI rather than drawing it, so the
--- honest thing when there is nothing to delegate to is to say so.
---
--- Requiring the module is not enough to know that. What a handover needs is
--- the `ci://` |BufReadCmd|, and that lives in ci.nvim's plugin file rather
--- than its module: with one loaded and not the other, `:CI` would open a
--- buffer nothing ever fills. The require comes first regardless, since for a
--- lazily loaded plugin it is what sources the plugin file.
--- @return table?
function M.available()
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
