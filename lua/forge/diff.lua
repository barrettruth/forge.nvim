local log = require('forge.log')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

--- diffs.nvim, if it is there to be used.
---
--- An optional dependency, on the same terms as ci.nvim: forge delegates
--- diffs rather than drawing them, so the honest thing when there is nothing
--- to delegate to is to say so. The require comes first because for a lazily
--- loaded plugin it is what sources the plugin file, and the flag is what
--- says the command it defines exists.
--- @return boolean
function M.available()
  pcall(require, 'diffs')
  return vim.g.loaded_diffs ~= nil
end

--- Show this pull request's diff in diffs.nvim.
---
--- A pull request is a merge-base diff, which is what `base...head` means to
--- git and to |:Diff| alike, so the handover is the spec and nothing else.
---
--- The refs are resolved here rather than passed on hopefully. They name
--- branches on github, and a branch you have never fetched is not a diff
--- anyone can draw: saying which one is missing beats a failure from a plugin
--- that was only told two names.
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

  local refs = vim.b[vim.api.nvim_get_current_buf()].forge or {}
  if not refs.base or not refs.head then
    log.err('this pull request did not say which branches it joins')
    return
  end

  local dir = vcs.dir()
  local base, head = vcs.rev(dir, refs.base), vcs.rev(dir, refs.head)
  if not base then
    return log.err(('%s is not here, so there is nothing to diff against'):format(refs.base))
  end
  if not head then
    return log.err(('%s is not here, so there is nothing to diff'):format(refs.head))
  end

  vim.cmd({ cmd = 'Diff', args = { 'review', ('%s...%s'):format(base, head) } })
end

return M
