local uri = require('forge.uri')

local M = {}

--- The forms github itself turns into a link, and no others.
---
--- A bare "owner/repo" is deliberately absent. It is also how a path is
--- spelled, so "spec/helpers.lua" in a body would open a repository nobody
--- named. The command line still takes it, because there you typed it.
---
--- Leaving it out settles a mention too, which arrives looking exactly like a
--- repository.
local LINKED = {
  '^#%d+$',
  '^[%w._-]+/[%w._-]+#%d+$',
  '^forge://',
  '^https?://github%.com/',
}

--- @param token string
--- @return boolean
local function linked(token)
  for _, pattern in ipairs(LINKED) do
    if token:find(pattern) then
      return true
    end
  end
  return false
end

--- The token under the cursor.
---
--- |<cfile>| rather than |<cWORD>|, because 'isfname' already leaves out the
--- brackets, quotes and trailing punctuation prose wraps a reference in:
--- "(#123)", "`#123`" and "#123." all arrive as "#123", and either half of a
--- markdown link answers for itself. Reading the WORD means peeling those off
--- afterwards, and peeling them off wrongly.
---
--- 'isfname' spells "@" as "any letter" rather than the character, so a
--- mention arrives without its sigil. Core widens it the same way for its own
--- |gx|. |expand()| raises E446 on nothing at all, and nothing may raise out
--- of a mapping.
--- @return string
local function token()
  return vim._with({ go = { isfname = vim.go.isfname .. ',@-@' } }, function()
    local ok, found = pcall(vim.fn.expand, '<cfile>')
    return ok and found --[[@as string]] or ''
  end)
end

--- What follows the token the cursor is in, or "" at the end of the line.
---
--- One character is enough to spot the label of a markdown link, which is
--- "#918]". Its target may name another repository entirely, and core reads
--- that out of the markdown tree, so forge declines the label and lets it.
--- @param tok string
--- @return string
local function trailing(tok)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local from = 1
  while true do
    local first, last = line:find(tok, from, true)
    if not first then
      return ''
    end
    if col >= first and col <= last then
      return line:sub(last + 1, last + 1)
    end
    from = first + 1
  end
end

--- The reference under the cursor.
--- @return string? token
--- @return string? err
function M.at_cursor()
  local tok = token()
  if tok == '' then
    return nil, 'nothing under the cursor'
  end
  if not linked(tok) then
    return nil, ('not a reference: %s'):format(tok)
  end
  return tok
end

--- The buffer name |gf| should open for `fname`. See 'includeexpr'.
---
--- A reference naming no repository means the one whose view it was read in,
--- which is the only repository it could have meant. Anything forge cannot
--- address is handed back unchanged, so |gf| on an ordinary path in a body
--- still opens the file.
--- @param fname string
--- @return string
function M.include(fname)
  local here = uri.parse(vim.api.nvim_buf_get_name(0))
  if not here or not linked(fname) then
    return fname
  end
  local t = uri.resolve(fname, here.collection)
  if not t then
    return fname
  end
  --- @type forge.Uri
  local there = {
    owner = t.owner or here.owner,
    repo = t.repo or here.repo,
    collection = t.collection,
    number = t.number,
    state = t.state,
  }
  return uri.tostring(there)
end

--- The github.com page a reference names, or nil for anything else.
---
--- A mention is only ever a page: there is no forge:// name for a user, so it
--- is the one reference |gf| cannot follow and |gx| can. Everything nil is
--- handed back to |gx|, whose job it already was.
--- @param selected string? the Visual selection, when there is one
--- @return string?
function M.web(selected)
  local tok = selected and vim.trim(selected) or token()
  local user = tok:match('^@([%w][%w-]*)$')
  if user then
    return ('https://github.com/%s'):format(user)
  end
  if not linked(tok) or (not selected and trailing(tok) == ']') then
    return nil
  end
  local here = uri.parse(vim.api.nvim_buf_get_name(0))
  if not here then
    return nil
  end
  local t = uri.resolve(tok, here.collection)
  if not t or not t.number then
    return nil
  end
  --- @type forge.Uri
  local there = {
    owner = t.owner or here.owner,
    repo = t.repo or here.repo,
    collection = t.collection,
    number = t.number,
  }
  return uri.web(there)
end

return M
