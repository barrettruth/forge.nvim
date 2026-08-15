--- Editing an item's title and body as text.
---
--- Writing the buffer is the submit, as it is for any 'acwrite' buffer: that is
--- what :w means for a netrw file over scp, for oil.nvim, for :Gwrite. The
--- other reading — that closing is the signal and :w merely a step — is git's,
--- and git only means it because it launched the editor and is waiting on it.
--- Nothing launches this one, and the plugin that tried has two open bugs from
--- it: a bare :w performing the action anyway, and a submit hung on a teardown
--- autocmd that silently ate the text whenever a config kept the buffer alive.
---
--- So :w submits, :wq and ZZ submit and close, and ZQ and :q! discard, all of
--- them out of Vim rather than out of forge. 'modified' is the only guard
--- against losing what you typed, so it is cleared when github says yes and
--- never before.

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

--- The title, then a blank line, then the body — a commit message's shape,
--- which is the one everybody already knows.
--- @param lines string[]
--- @return string title
--- @return string body
local function split(lines)
  local body = {}
  for i = 2, #lines do
    if #body > 0 or vim.trim(lines[i]) ~= '' then
      body[#body + 1] = lines[i]
    end
  end
  return vim.trim(lines[1] or ''), table.concat(body, '\n')
end

--- @param buf integer
--- @param u forge.Uri the item being edited
--- @param var forge.ItemVar
local function write(buf, u, var)
  local title, body = split(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
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
--- words twice. The name is a `forge://` one for the sake of reading it, but
--- |uri.parse| does not know it, which is what keeps every `forge://*`
--- autocmd off a buffer that is not a view.
--- @param var forge.ItemVar
function M.open(var)
  local u = view.current()
  if not u or not u.number then
    return
  end
  local name = ('%s/edit'):format(uri.tostring(u))

  local buf = view.buffer_named(name) or vim.api.nvim_create_buf(true, false)
  if vim.api.nvim_buf_get_name(buf) ~= name then
    vim.api.nvim_buf_set_name(buf, name)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(var.edit or '', '\n'))
    vim.bo[buf].modified = false
  end
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].filetype = 'markdown'

  --- The buffer outlives any one opening of it, and each carries its own
  --- window to answer into, so the latest owns the write rather than joining
  --- a queue of them.
  vim.api.nvim_clear_autocmds({ buffer = buf, event = 'BufWriteCmd' })
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    desc = 'send an edited title and body to github',
    callback = function()
      write(buf, u, var)
    end,
  })

  vim.cmd.buffer(buf)
  --- Nothing else says the first line is the title: the buffer is markdown, so
  --- it draws as ordinary prose while the body's own headings do not. Written
  --- rather than templated, because none of it comes from github.
  vim.wo[0][0].winbar = ('%%#Title#EDIT%%* %%#Tag#%s%%* %%#Comment#| first line is the title | :w sends it%%*'):format(
    var.tag
  )
end

return M
