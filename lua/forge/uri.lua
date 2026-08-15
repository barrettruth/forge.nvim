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
--- @field state 'OPEN'|'CLOSED'? which half a list holds; unused by an item
--- @field head boolean? the pull request for the change you are on

--- A view forge can address, which is a target github has already answered.
---
--- An item is a collection with a number; without one it is the list itself.
--- @class forge.Uri : forge.Target
--- @field owner string
--- @field repo string

local M = {}

local SCHEME = 'forge://'

--- github.com's own path segments, which forge does not borrow. Theirs are
--- plural for an issue list and a single issue, plural for a pull request
--- list and singular for a single pull request; ours are always "prs".
local WEB = {
  issues = { list = 'issues', member = 'issues', filter = 'issue' },
  prs = { list = 'pulls', member = 'pull', filter = 'pr' },
}

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
    state = t.state,
  }
end

--- @param uri forge.Uri
--- @return string
function M.tostring(uri)
  local base = ('%s%s/%s/%s'):format(SCHEME, uri.owner, uri.repo, uri.collection)
  if uri.number then
    return ('%s/%d'):format(base, uri.number)
  end
  if uri.state == 'CLOSED' then
    return base .. '/closed'
  end
  return base
end

--- The github.com page a view corresponds to.
---
--- Close to the path with the scheme swapped, but not a translation forge
--- avoids: github spells a closed list as a query, names a single pull
--- request in the singular, and calls the collection "pulls".
--- @param uri forge.Uri
--- @return string
function M.web(uri)
  local base = ('https://github.com/%s/%s'):format(uri.owner, uri.repo)
  local web = WEB[uri.collection]
  if uri.number then
    return ('%s/%s/%d'):format(base, web.member, uri.number)
  end
  if uri.state == 'CLOSED' then
    return ('%s/%s?q=is%%3A%s+is%%3Aclosed'):format(base, web.list, web.filter)
  end
  return ('%s/%s'):format(base, web.list)
end

--- @param str string
--- @return forge.Uri?
function M.parse(str)
  local rest = str:match('^' .. SCHEME .. '(.+)$')
  if not rest then
    return nil
  end

  local owner, repo, collection, number = rest:match('^([^/]+)/([^/]+)/(%a+)/(%d+)$')
  if owner and WEB[collection] then
    return {
      owner = owner,
      repo = repo,
      collection = collection,
      number = tonumber(number),
    }
  end

  owner, repo, collection = rest:match('^([^/]+)/([^/]+)/(%a+)/closed$')
  if owner and WEB[collection] then
    return { owner = owner, repo = repo, collection = collection, state = 'CLOSED' }
  end

  owner, repo, collection = rest:match('^([^/]+)/([^/]+)/(%a+)$')
  if owner and WEB[collection] then
    return { owner = owner, repo = repo, collection = collection, state = 'OPEN' }
  end

  return nil
end

--- Resolve what the user typed into a target.
---
--- Accepts a forge:// URI, a github.com URL, an `owner/repo#number` slug, a
--- bare `owner/repo`, a bare number, or nothing at all. The forms that name no
--- repository leave `owner` and `repo` unset for gh to answer; this never
--- shells out, and never fails for want of a remote.
---
--- Nothing at all means the issue list, or the pull request for the branch
--- checked out here. Only a pull request has an obvious referent: nothing
--- identifies "the current issue".
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
    return { owner = owner, repo = repo, collection = named, state = 'OPEN' }
  end

  owner, repo, number = target:match('^([%w._-]+)/([%w._-]+)#(%d+)$')
  if owner then
    return { owner = owner, repo = repo, collection = collection, number = tonumber(number) }
  end
  owner, repo = target:match('^([%w._-]+)/([%w._-]+)$')
  if owner then
    return { owner = owner, repo = repo, collection = collection, state = 'OPEN' }
  end

  if target == '@' then
    if collection ~= 'prs' then
      return nil, 'nothing identifies the issue you are on'
    end
    return { collection = 'prs', head = true }
  end
  if target == '' then
    return { collection = collection, state = 'OPEN' }
  end
  if target:match('^#?%d+$') then
    return { collection = collection, number = tonumber(target:match('%d+')) }
  end
  return nil, 'cannot resolve: ' .. target
end

return M
