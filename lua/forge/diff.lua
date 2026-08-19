local log = require('forge.log')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

--- diffs.nvim, if it is there to be used.
---
--- An installed plugin is not a loaded one. Under `pack/*/opt` nothing is on
--- the runtimepath until |:packadd|, so requiring first would call an
--- installed diffs.nvim missing merely because its own trigger had not fired.
--- @return boolean
function M.available()
  if not vim.g.loaded_diffs then
    pcall(vim.cmd.packadd, 'diffs.nvim')
  end
  pcall(require, 'diffs')
  return vim.g.loaded_diffs ~= nil
end

--- Show this pull request's diff in diffs.nvim.
---
--- A pull request is a merge-base diff, which is what `base...head` means to
--- git and to |:Diff| alike, so the handover is the spec and nothing else.
--- Both ends are fetched first, unconditionally: diffs.nvim draws from the
--- object store, and a pull request you did not write is never already there.
--- The window is named before the fetch, because by the time one comes back
--- the current window is whatever you wandered to.
function M.show()
  local u = view.current()
  local be = require('forge.backend').of(u and u.host)
  local nouns = be.nouns.prs
  if not u or u.collection ~= 'prs' or not u.number then
    log.warn(('no %s here to diff'):format(nouns.one))
    return
  end
  if not M.available() then
    log.err('diffs.nvim is not available')
    return
  end

  --- @type forge.ItemVar
  local refs = vim.b[vim.api.nvim_get_current_buf()].forge or {}
  if not refs.base or not refs.remote then
    log.err(('this %s did not say what it merges into'):format(nouns.one))
    return
  end

  local from = vim.api.nvim_get_current_win()
  local ref = be.pull_ref(u.number)
  vcs.fetch_pull(vcs.dir(), refs.remote, u.number, refs.base, ref, function(base, head)
    require('diffs').open_review({
      base = base,
      target = head,
      mode = 'merge-base',
    }, { replace_win = vim.api.nvim_win_is_valid(from) and from or nil })
  end)
end

return M
