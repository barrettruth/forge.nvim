local uri = require('forge.uri')

local M = {}

--- The forms github itself turns into a link, and no others.
---
--- A bare "owner/repo" is absent. It is also how a path is spelled.
--- "spec/helpers.lua" in a body would open a repository nobody named. A
--- mention arrives looking exactly the same. The command line still takes one.
---
--- The github.com forms match on the path, not the host alone. Most of what
--- github serves is not an item. A url `uri.resolve` does not recognise
--- becomes a search. That opens the bare list with its query dropped.
local LINKED = {
  '^#%d+$',
  '^[%w._-]+/[%w._/-]+#%d+$',
  -- gitlab's merge request sigil. The one form that names its own collection
  -- without being asked.
  '^!%d+$',
  '^[%w._-]+/[%w._/-]+!%d+$',
  '^forge://',
  -- The frontier ends the word, `%z` standing for the end of the string.
  '^https?://github%.com/[^/]+/[^/]+/issues%f[%z/?#]',
  '^https?://github%.com/[^/]+/[^/]+/pulls?%f[%z/?#]',
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
--- |<cfile>| rather than |<cWORD>|. 'isfname' already leaves out the
--- brackets, quotes and trailing punctuation prose wraps a reference in.
--- "(#123)", "`#123`" and "#123." all arrive as "#123". Reading the WORD means
--- peeling those off afterwards, and peeling them off wrongly.
---
--- 'isfname' spells "@" as "any letter", not the character. A mention would
--- arrive without its sigil. Core widens it the same way for |gx|. Neither
--- "!" nor "&" is in it at all. Those are gitlab's sigils for a merge request
--- and an epic, and both would arrive as bare numbers. |expand()| raises E446
--- on nothing at all, and nothing may raise out of a mapping.
--- @return string
local function token()
  return vim._with({ go = { isfname = vim.go.isfname .. ',@-@,!,&' } }, function()
    local ok, found = pcall(vim.fn.expand, '<cfile>')
    return ok and found --[[@as string]] or ''
  end)
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
--- A reference naming no repository means the one whose view it was read in.
--- Anything forge cannot address is handed back unchanged. |gf| on an ordinary
--- path in a body still opens the file.
--- @param fname string
--- @return string
function M.include(fname)
  local here = uri.parse(vim.api.nvim_buf_get_name(0))
  if not here or not linked(fname) then
    return fname
  end
  -- github draws issues and pull requests from one sequence. "#123" there
  -- means whichever the view is already showing. Everywhere else numbers them
  -- apart, and "#" is the issue sigil whatever you are reading.
  local meant = here.host == 'github.com' and here.collection or 'issues'
  local t = uri.resolve(fname, meant)
  if not t then
    return fname
  end
  --- @type forge.Uri
  local there = {
    host = t.host or here.host,
    project = t.project or here.project,
    collection = t.collection,
    number = t.number,
  }
  return uri.tostring(there)
end

return M
