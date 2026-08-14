--- @alias forge.Collection 'issues'|'pulls'

--- A view forge can address.
---
--- An item is a collection with a number; without one it is the list itself.
--- @class forge.Uri
--- @field owner string
--- @field repo string
--- @field collection forge.Collection
--- @field number integer? nil for a list
--- @field state 'OPEN'|'CLOSED'? which half a list holds; unused by an item

local M = {}

local SCHEME = 'forge://'

--- github.com's own path segment for one member of a collection. Theirs is
--- plural for issues and singular for pull requests; ours is always plural.
local WEB_MEMBER = { issues = 'issues', pulls = 'pull' }

--- @param url string
--- @return string? owner
--- @return string? repo
local function split_remote(url)
  local owner, repo = url:match('github%.com[:/]([^/]+)/([^/]+)$')
  if not owner then
    return nil, nil
  end
  return owner, (repo:gsub('%.git$', ''))
end

--- The owner and repo of the repository containing the working directory.
--- @return string? owner
--- @return string? repo
function M.origin()
  local out = vim.system({ 'git', 'remote', 'get-url', 'origin' }, { text = true }):wait()
  if out.code ~= 0 then
    return nil, nil
  end
  return split_remote(vim.trim(out.stdout))
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
--- Mostly the path with the scheme swapped, since forge:// borrows github's
--- own. Two exceptions: github spells a closed list as a query, and names a
--- single pull request in the singular.
--- @param uri forge.Uri
--- @return string
function M.web(uri)
  local base = ('https://github.com/%s/%s'):format(uri.owner, uri.repo)
  if uri.number then
    return ('%s/%s/%d'):format(base, WEB_MEMBER[uri.collection], uri.number)
  end
  if uri.state == 'CLOSED' then
    local what = uri.collection == 'pulls' and 'pr' or 'issue'
    return ('%s/%s?q=is%%3A%s+is%%3Aclosed'):format(base, uri.collection, what)
  end
  return ('%s/%s'):format(base, uri.collection)
end

--- @param str string
--- @return forge.Uri?
function M.parse(str)
  local rest = str:match('^' .. SCHEME .. '(.+)$')
  if not rest then
    return nil
  end

  local owner, repo, collection, number = rest:match('^([^/]+)/([^/]+)/(%a+)/(%d+)$')
  if owner and WEB_MEMBER[collection] then
    return {
      owner = owner,
      repo = repo,
      collection = collection,
      number = tonumber(number),
    }
  end

  owner, repo, collection = rest:match('^([^/]+)/([^/]+)/(%a+)/closed$')
  if owner and WEB_MEMBER[collection] then
    return { owner = owner, repo = repo, collection = collection, state = 'CLOSED' }
  end

  owner, repo, collection = rest:match('^([^/]+)/([^/]+)/(%a+)$')
  if owner and WEB_MEMBER[collection] then
    return { owner = owner, repo = repo, collection = collection, state = 'OPEN' }
  end

  return nil
end

--- Resolve what the user typed into a view.
---
--- Accepts a forge:// URI, a github.com URL, an `owner/repo#number` slug, a
--- bare `owner/repo`, a bare number, or nothing at all. The last three need a
--- repository, which comes from the origin remote.
---
--- `collection` says which of issues or pull requests a bare number means; it
--- is the only thing a caller's intent decides. Every other form says for
--- itself, and may disagree with the caller — that is for the caller to catch.
--- @param target string?
--- @param collection forge.Collection
--- @return forge.Uri? uri
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
      collection = member == 'pull' and 'pulls' or 'issues',
      number = tonumber(number),
    }
  end
  owner, repo, member = target:match('^https?://github%.com/([^/]+)/([^/]+)/(%a+)/?$')
  if owner and WEB_MEMBER[member] then
    return { owner = owner, repo = repo, collection = member, state = 'OPEN' }
  end

  owner, repo, number = target:match('^([%w._-]+)/([%w._-]+)#(%d+)$')
  if owner then
    return { owner = owner, repo = repo, collection = collection, number = tonumber(number) }
  end
  owner, repo = target:match('^([%w._-]+)/([%w._-]+)$')
  if owner then
    return { owner = owner, repo = repo, collection = collection, state = 'OPEN' }
  end

  local origin_owner, origin_repo = M.origin()
  if not origin_owner then
    return nil, 'no github origin remote here'
  end
  if target == '' then
    return {
      owner = origin_owner,
      repo = origin_repo,
      collection = collection,
      state = 'OPEN',
    }
  end
  if target:match('^#?%d+$') then
    return {
      owner = origin_owner,
      repo = origin_repo,
      collection = collection,
      number = tonumber(target:match('%d+')),
    }
  end
  return nil, 'cannot resolve: ' .. target
end

return M
