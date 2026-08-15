--- @alias forge.Collection 'issues'|'prs'

--- What the user asked for, before github has said which repository that is.
---
--- `owner` and `repo` are absent when the target did not name a repository.
--- Nothing here fills them in: gh resolves the repository, and the answer
--- comes back with the view.
--- @class forge.Target
--- @field collection forge.Collection
--- @field owner string?
--- @field repo string?
--- @field number integer? nil for a list
--- @field query string? a github search, for a list narrowed by one
--- @field head boolean? the pull request for the change you are on

--- A view forge can address, which is a target github has already answered.
---
--- An item is a collection with a number; without one it is the list itself.
--- @class forge.Uri : forge.Target
--- @field owner string
--- @field repo string

local M = {}

local SCHEME = 'forge://'

--- What a forge:// name may hold. github's own spelling of these — plural for
--- a pull request list and singular for one of them — is never needed here: a
--- view carries the url github gave it.
local COLLECTIONS = { issues = true, prs = true }

--- What survives into a name unescaped. Everything else is percent-encoded,
--- and `%` and `#` above all: Neovim expands both in a command line, so a
--- name carrying one raw cannot be typed at |:edit| without a backslash.
local SAFE = '[^%w._~:/@,+-]'

--- @param query string
--- @return string
local function encode(query)
  return (query:gsub(SAFE, function(c)
    return ('%%%02X'):format(c:byte())
  end))
end

--- @param encoded string
--- @return string
local function decode(encoded)
  return (encoded:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

--- The view a response describes, named by the repository github answered for.
---
--- A target that named no repository is sent with gh's placeholders, so the
--- name a view is filed under arrives with the view rather than being guessed
--- at beforehand. A target that named one is still filed under github's
--- spelling of it, which is the one that round-trips.
--- @param slug string? "owner/repo", as github spells it
--- @param t forge.Target
--- @return forge.Uri?
function M.of(slug, t)
  local owner, repo = (slug or ''):match('^([^/]+)/([^/]+)$')
  if not owner then
    return nil
  end
  return {
    owner = owner,
    repo = repo,
    collection = t.collection,
    number = t.number,
    query = t.query,
  }
end

--- @param uri forge.Uri
--- @return string
function M.tostring(uri)
  local base = ('%s%s/%s/%s'):format(SCHEME, uri.owner, uri.repo, uri.collection)
  if uri.number then
    return ('%s/%d'):format(base, uri.number)
  end
  if uri.query then
    return ('%s?q=%s'):format(base, encode(uri.query))
  end
  return base
end

--- @param str string
--- @return forge.Uri?
function M.parse(str)
  local rest = str:match('^' .. SCHEME .. '(.+)$')
  if not rest then
    return nil
  end

  local owner, repo, collection, number = rest:match('^([^/]+)/([^/]+)/(%a+)/(%d+)$')
  if owner and COLLECTIONS[collection] then
    return {
      owner = owner,
      repo = repo,
      collection = collection,
      number = tonumber(number),
    }
  end

  local query
  owner, repo, collection, query = rest:match('^([^/]+)/([^/]+)/(%a+)%?q=(.+)$')
  if owner and COLLECTIONS[collection] then
    return { owner = owner, repo = repo, collection = collection, query = decode(query) }
  end

  owner, repo, collection = rest:match('^([^/]+)/([^/]+)/(%a+)$')
  if owner and COLLECTIONS[collection] then
    return { owner = owner, repo = repo, collection = collection }
  end

  return nil
end

--- Resolve what the user typed into a target. See |:Issue| for the forms.
---
--- A form naming no repository leaves `owner` and `repo` unset for gh to
--- answer, so this never shells out and never fails for want of a remote.
---
--- `collection` says which of issues or pull requests a bare number means; it
--- is the only thing a caller's intent decides. Every other form says for
--- itself, and may disagree with the caller — that is for the caller to catch.
--- @param target string?
--- @param collection forge.Collection
--- @return forge.Target? target
--- @return string? err
function M.resolve(target, collection)
  target = vim.trim(target or '')

  if target:find('^' .. SCHEME) then
    local parsed = M.parse(target)
    if not parsed then
      return nil, 'not a forge uri: ' .. target
    end
    return parsed
  end

  local owner, repo, member, number =
    target:match('^https?://github%.com/([^/]+)/([^/]+)/(%a+)/(%d+)')
  if owner and (member == 'issues' or member == 'pull') then
    return {
      owner = owner,
      repo = repo,
      collection = member == 'pull' and 'prs' or 'issues',
      number = tonumber(number),
    }
  end
  owner, repo, member = target:match('^https?://github%.com/([^/]+)/([^/]+)/(%a+)/?$')
  if owner and (member == 'issues' or member == 'pulls') then
    local named = member == 'pulls' and 'prs' or 'issues'
    return { owner = owner, repo = repo, collection = named }
  end

  owner, repo, number = target:match('^([%w._-]+)/([%w._-]+)#(%d+)$')
  if owner then
    return { owner = owner, repo = repo, collection = collection, number = tonumber(number) }
  end
  owner, repo = target:match('^([%w._-]+)/([%w._-]+)$')
  if owner then
    return { owner = owner, repo = repo, collection = collection }
  end

  if target == '@' then
    if collection ~= 'prs' then
      return nil, 'nothing identifies the issue you are on'
    end
    return { collection = 'prs', head = true }
  end
  if target == '' then
    return { collection = collection }
  end
  if target:match('^#?%d+$') then
    return { collection = collection, number = tonumber(target:match('%d+')) }
  end
  --- Anything that names nothing forge knows is a search. github's own syntax
  --- needs no sigil to tell it from a number or a slug, since neither of those
  --- reaches here.
  return { collection = collection, query = target }
end

return M
