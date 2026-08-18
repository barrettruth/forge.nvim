--- Editing an item's title and body as text. What writing the buffer means is
--- forge.compose's to say.

local compose = require('forge.compose')
local gh = require('forge.gh')
local log = require('forge.log')
local uri = require('forge.uri')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

local ISSUE = [[
mutation($id: ID!, $title: String!, $body: String!) {
  updateIssue(input: {id: $id, title: $title, body: $body}) { clientMutationId }
}
]]

local PR = [[
mutation($id: ID!, $title: String!, $body: String!) {
  updatePullRequest(input: {pullRequestId: $id, title: $title, body: $body}) { clientMutationId }
}
]]

--- @param lines string[]
--- @param buf integer
--- @param u forge.Uri the item being edited
--- @param var forge.ItemVar
local function write(lines, buf, u, var)
  local title, body = compose.split(lines)
  if title == '' then
    log.err('an item needs a title')
    return
  end

  local cwd = vcs.dir()
  gh.graphql({
    desc = ('%s edited'):format(var.tag),
    query = u.collection == 'prs' and PR or ISSUE,
    variables = { id = var.id, title = title, body = body },
    cwd = cwd,
  }, function()
    --- Only now: until github has said yes, what is in the buffer is the only
    --- copy of it, and a buffer that is not 'modified' can be closed by
    --- anything without a word.
    if vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modified = false
    end
    --- Into its own buffer and no further: the window it would have taken is
    --- the one still showing what was written, and it is fresh by the time
    --- "-" goes back to it.
    view.open(u, { keep = true, hidden = true, cwd = cwd })
  end)
end

--- Open the title and body of the item being viewed, to be edited.
---
--- Over the view rather than beside it, as "dd" and "dc" do: nearly all of
--- what an item shows is its title and its body, so a split would be the same
--- words twice.
--- @param var forge.ItemVar
function M.open(var)
  local u = view.current()
  if not u or not u.number then
    return
  end

  compose.open({
    name = ('%s/edit'):format(uri.tostring(u)),
    text = var.edit or '',
    filetype = 'markdown',
    desc = 'send an edited title and body to github',
    label = var.label,
    tag = var.tag,
    mode = 'EDIT',
    on_write = function(lines, buf)
      write(lines, buf, u, var)
    end,
  })
end

return M
