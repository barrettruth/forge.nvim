local log = require('forge.log')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

--- diffs.nvim, if it is there to be used.
---
--- An optional dependency, on the same terms as ci.nvim: forge delegates
--- diffs rather than drawing them, so the honest thing when there is nothing
--- to delegate to is to say so.
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
---
--- Both ends are fetched first. diffs.nvim draws from the object store rather
--- than from a patch, and a pull request you did not write is never already
--- there: refusing on that would refuse on almost every pull request worth
--- looking at.
---
--- The diff takes this window rather than splitting off it, as the checks do.
--- It is the same pull request seen differently, and a review map is the
--- widest and longest thing forge hands anywhere: half a window is the worst
--- place for it. The window is named before the fetch, because by the time
--- one comes back the current window is whatever you wandered to.
function M.show()
  local u = view.current()
  if not u or u.collection ~= 'prs' or not u.number then
    log.warn('no pull request here to diff')
    return
  end
  if not M.available() then
    log.err('diffs.nvim is not available')
    return
  end

  --- @type forge.BufVar
  local refs = vim.b[vim.api.nvim_get_current_buf()].forge or {}
  if not refs.base then
    log.err('this pull request did not say what it merges into')
    return
  end

  local from = vim.api.nvim_get_current_win()
  local url = ('https://github.com/%s/%s'):format(u.owner, u.repo)
  vcs.fetch_pull(vcs.dir(), url, u.number, refs.base, function(base, head)
    require('diffs').open_review({
      base = base,
      target = head,
      mode = 'merge-base',
    }, { replace_win = vim.api.nvim_win_is_valid(from) and from or nil })
  end)
end

return M
