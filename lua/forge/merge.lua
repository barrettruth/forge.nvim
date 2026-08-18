--- Writing the commit message a merge will carry. What writing the buffer
--- means is forge.compose's to say.

local compose = require('forge.compose')
local gh = require('forge.gh')
local log = require('forge.log')
local uri = require('forge.uri')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

--- @param method 'SQUASH'|'MERGE'
--- @return string
local function merging(method)
  return ([[
mutation($id: ID!, $oid: GitObjectID!, $headline: String!, $body: String!) {
  mergePullRequest(input: {
    pullRequestId: $id
    mergeMethod: %s
    expectedHeadOid: $oid
    commitHeadline: $headline
    commitBody: $body
  }) { clientMutationId }
}
]]):format(method)
end

--- github's enum spells a merge commit "MERGE", which alone would read badly
--- in either place.
local MODE = { SQUASH = 'SQUASH', MERGE = 'MERGE COMMIT' }
local NAME = { SQUASH = 'squash', MERGE = 'commit' }

--- @param lines string[]
--- @param buf integer
--- @param u forge.Uri
--- @param var forge.ItemVar
--- @param method 'SQUASH'|'MERGE'
local function write(lines, buf, u, var, method)
  local headline, body = compose.split(lines)
  if headline == '' then
    log.err('a merge commit needs a subject')
    return
  end

  local win = vim.api.nvim_get_current_win()
  local cwd = vcs.dir()
  gh.graphql({
    desc = ('%s merged'):format(var.tag),
    query = merging(method),
    --- An empty body is sent as one. Leaving the field out has github compose
    --- the default this buffer was filled with and then discarded.
    variables = { id = var.id, oid = var.oid, headline = headline, body = body },
    cwd = cwd,
  }, function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modified = false
    end
    --- Into the window the message was written in, which leaves nothing to
    --- close: 'bufhidden' is "wipe", so the pull request taking the window
    --- takes the buffer away with it.
    view.open(u, { keep = true, win = win, cwd = cwd })
  end)
end

--- Write the commit message for a merge, and merge on writing it.
--- @param var forge.ItemVar
--- @param method 'SQUASH'|'MERGE'
function M.open(var, method)
  local u = view.current()
  if not u or not u.number then
    return
  end

  local message = (var.merge or {})[method] or {}
  compose.open({
    --- Named for the method, so picking one after the other does not hand back
    --- the message written for the first.
    name = ('%s/merge/%s'):format(uri.tostring(u), NAME[method]),
    text = ('%s\n\n%s'):format(message.headline or '', message.body or ''),
    filetype = 'gitcommit',
    desc = 'merge the pull request with the message written here',
    label = var.label,
    tag = var.tag,
    mode = MODE[method] .. (var.can_bypass and ' BYPASS' or ''),
    mode_hl = var.can_bypass and 'ErrorMsg' or nil,
    split = true,
    on_write = function(lines, buf)
      write(lines, buf, u, var, method)
    end,
  })
end

return M
