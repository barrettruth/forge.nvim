local uri = require('forge.uri')

local M = {}

--- The forms github itself turns into a link, and no others.
---
--- A bare "owner/repo" is deliberately absent. It is also how a path is
--- spelled, so "spec/helpers.lua" in a body would open a repository nobody
--- named. The command line still takes it, because there you typed it.
---
--- Leaving it out settles a mention too: <cfile> drops the "@", since
--- 'isfname' spells "@" as "any letter" rather than the character itself, and
--- "@org/team-name" would otherwise arrive looking exactly like a repository.
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

--- The reference under the cursor.
---
--- |<cfile>| rather than |<cWORD>|, because 'isfname' already leaves out the
--- brackets, quotes and trailing punctuation prose wraps a reference in:
--- "(#123)", "`#123`" and "#123." all arrive as "#123", and either half of a
--- markdown link answers for itself. Reading the WORD means peeling those off
--- afterwards, and peeling them off wrongly.
--- |expand()| raises E446 rather than answering emptily when there is nothing
--- under the cursor, and a command is not a place to raise from.
--- @return string? token
--- @return string? err
function M.at_cursor()
  local ok, found = pcall(vim.fn.expand, '<cfile>')
  local token = ok and found --[[@as string]] or ''
  if token == '' then
    return nil, 'nothing under the cursor'
  end
  if not linked(token) then
    return nil, ('not a reference: %s'):format(token)
  end
  return token
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

return M
