--- @class forge.Uri
--- @field owner string
--- @field repo string
--- @field kind 'issues'|'issue'
--- @field number integer?
--- @field state 'OPEN'|'CLOSED'? which issues a list holds; open when absent

local M = {}

local SCHEME = 'forge://'

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
  if uri.kind == 'issue' then
    return ('%s%s/%s/issues/%d'):format(SCHEME, uri.owner, uri.repo, uri.number)
  end
  if uri.state == 'CLOSED' then
    return ('%s%s/%s/issues/closed'):format(SCHEME, uri.owner, uri.repo)
  end
  return ('%s%s/%s/issues'):format(SCHEME, uri.owner, uri.repo)
end

--- The github.com page a view corresponds to.
---
--- Mostly the path with the scheme swapped, since forge:// borrows github's
--- own. A closed list is the exception: github spells that filter as a query.
--- @param uri forge.Uri
--- @return string
function M.web(uri)
  local base = ('https://github.com/%s/%s'):format(uri.owner, uri.repo)
  if uri.kind == 'issue' then
    return ('%s/issues/%d'):format(base, uri.number)
  end
  if uri.state == 'CLOSED' then
    return ('%s/issues?q=is%%3Aissue+is%%3Aclosed'):format(base)
  end
  return ('%s/issues'):format(base)
end

--- @param str string
--- @return forge.Uri?
function M.parse(str)
  local rest = str:match('^' .. SCHEME .. '(.+)$')
  if not rest then
    return nil
  end
  local owner, repo, number = rest:match('^([^/]+)/([^/]+)/issues/(%d+)$')
  if owner then
    return { owner = owner, repo = repo, kind = 'issue', number = tonumber(number) }
  end
  owner, repo = rest:match('^([^/]+)/([^/]+)/issues/closed$')
  if owner then
    return { owner = owner, repo = repo, kind = 'issues', state = 'CLOSED' }
  end
  owner, repo = rest:match('^([^/]+)/([^/]+)/issues$')
  if owner then
    return { owner = owner, repo = repo, kind = 'issues', state = 'OPEN' }
  end
  return nil
end

--- Resolve what the user typed into a URI.
---
--- Accepts, in order: a forge:// URI, a github.com URL, an `owner/repo#number`
--- slug, a bare `owner/repo`, a bare issue number, or nothing at all. The last
--- two need a repository, which comes from the origin remote.
--- @param target string?
--- @return forge.Uri? uri
--- @return string? err
function M.resolve(target)
  target = vim.trim(target or '')

  if target:find('^' .. SCHEME) then
    return M.parse(target) or nil, 'not a forge uri: ' .. target
  end

  local owner, repo, number = target:match('^https?://github%.com/([^/]+)/([^/]+)/issues/(%d+)')
  if owner then
    return { owner = owner, repo = repo, kind = 'issue', number = tonumber(number) }
  end
  owner, repo = target:match('^https?://github%.com/([^/]+)/([^/]+)/issues/?$')
  if owner then
    return { owner = owner, repo = repo, kind = 'issues' }
  end
  owner, repo, number = target:match('^([%w._-]+)/([%w._-]+)#(%d+)$')
  if owner then
    return { owner = owner, repo = repo, kind = 'issue', number = tonumber(number) }
  end
  owner, repo = target:match('^([%w._-]+)/([%w._-]+)$')
  if owner then
    return { owner = owner, repo = repo, kind = 'issues' }
  end

  local origin_owner, origin_repo = M.origin()
  if not origin_owner then
    return nil, 'no github origin remote here'
  end
  if target == '' then
    return { owner = origin_owner, repo = origin_repo, kind = 'issues' }
  end
  if target:match('^#?%d+$') then
    return {
      owner = origin_owner,
      repo = origin_repo,
      kind = 'issue',
      number = tonumber(target:match('%d+')),
    }
  end
  return nil, 'cannot resolve: ' .. target
end

return M
