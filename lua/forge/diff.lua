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
--- Both ends are fetched first. diffs.nvim draws from the object store rather
--- than from a patch, and a pull request you did not write is never already
--- there: refusing on that would refuse on almost every pull request worth
--- looking at.
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
  if not refs.base then
    log.err('this pull request did not say what it merges into')
    return
  end

  local url = ('https://github.com/%s/%s'):format(u.owner, u.repo)
  vcs.fetch_pull(vcs.dir(), url, u.number, refs.base, function(base, head)
    vim.cmd({ cmd = 'Diff', args = { 'review', ('%s...%s'):format(base, head) } })
  end)
end

return M
