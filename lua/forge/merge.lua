--- Writing the commit message a merge will carry. What writing the buffer
--- means is forge.compose's to say.

local backend = require('forge.backend')
local compose = require('forge.compose')
local log = require('forge.log')
local uri = require('forge.uri')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

--- github's enum spells a merge commit "MERGE", which alone would read badly
--- in either place.
local MODE = { SQUASH = 'SQUASH', MERGE = 'MERGE COMMIT' }
local NAME = { SQUASH = 'squash', MERGE = 'commit' }

--- @param lines string[]
--- @param buf integer
--- @param u forge.Uri
--- @param var forge.ItemVar
--- @param method 'SQUASH'|'MERGE'
--- @param auto boolean
local function write(lines, buf, u, var, method, auto)
  local headline, body = compose.split(lines)
  if headline == '' then
    log.err('a merge commit needs a subject')
    return
  end

  local be = backend.of(u.host)
  if not be then
    return
  end

  local win = vim.api.nvim_get_current_win()
  local cwd = vcs.dir()
  be.write({
    kind = 'merge',
    desc = ('%s %s'):format(var.tag, auto and 'merging when it is ready' or 'merged'),
    collection = u.collection,
    var = var,
    method = method,
    auto = auto,
    headline = headline,
    body = body,
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
--- @param auto boolean? wait for github to allow it rather than merging now
function M.open(var, method, auto)
  local u = view.current()
  if not u or not u.number then
    return
  end

  auto = auto == true
  local message = (var.merge or {})[method] or {}
  local nouns = backend.of(u.host).nouns.prs
  compose.open({
    --- Named for the method, and for whether it waits, so picking one after
    --- another does not hand back the message written for the first.
    name = ('%s/%s/%s'):format(uri.tostring(u), auto and 'automerge' or 'merge', NAME[method]),
    text = ('%s\n\n%s'):format(message.headline or '', message.body or ''),
    filetype = 'gitcommit',
    desc = ('merge the %s with the message written here'):format(nouns.one),
    label = var.label,
    tag = var.tag,
    --- A bypass goes past a rule, so it is drawn as an error. A merge that
    --- waits goes past nothing, and github does not honour a bypass when it
    --- comes to make one, so the two words never appear together.
    mode = (auto and 'AUTO ' or '')
      .. MODE[method]
      .. ((not auto and var.can_bypass) and ' BYPASS' or ''),
    mode_hl = (not auto and var.can_bypass) and 'ErrorMsg' or nil,
    split = true,
    on_write = function(lines, buf)
      write(lines, buf, u, var, method, auto)
    end,
  })
end

return M
