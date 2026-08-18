--- @alias forge.Collection 'issues'|'prs'

--- What the user asked for, before the forge has said which repository that is.
---
--- `project` is absent when the target did not name a repository. Nothing here
--- fills it in: the CLI resolves the repository, and the answer comes back with
--- the view. `host` is absent for the same reason, and defaults to github.com
--- only once a backend has to be chosen.
--- @class forge.Target
--- @field collection forge.Collection
--- @field host string? the forge, by hostname
--- @field project string? the full path, which on gitlab may nest groups
--- @field number integer? nil for a list
--- @field query string? a search, for a list narrowed by one
--- @field head boolean? the pull request for the change you are on

--- A view forge can address, which is a target a forge has already answered.
---
--- An item is a collection with a number; without one it is the list itself.
--- @class forge.Uri : forge.Target
--- @field host string
--- @field project string

local M = {}

local SCHEME = 'forge://'

--- The forge a target that never named one belongs to. A name is always
--- complete, so this is where an unanswered target acquires its host.
local DEFAULT_HOST = 'github.com'

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

--- The view a response describes, named by the repository the forge answered
--- for.
---
--- A target that named no repository is sent with the CLI's placeholders, so
--- the name a view is filed under arrives with the view rather than being
--- guessed at beforehand. A target that named one is still filed under the
--- forge's spelling of it, which is the one that round-trips.
--- @param path string? the project's full path, as the forge spells it
--- @param t forge.Target
--- @return forge.Uri?
function M.of(path, t)
  if not path or not path:find('/') then
    return nil
  end
  return {
    host = t.host or DEFAULT_HOST,
    project = path,
    collection = t.collection,
    number = t.number,
    query = t.query,
  }
end

--- @param uri forge.Uri
--- @return string
function M.tostring(uri)
  local base = ('%s%s/%s/%s'):format(SCHEME, uri.host or DEFAULT_HOST, uri.project, uri.collection)
  if uri.number then
    return ('%s/%d'):format(base, uri.number)
  end
  if uri.query then
    return ('%s?q=%s'):format(base, encode(uri.query))
  end
  return base
end

--- Split a name into host, project, collection and whichever of a number or a
--- query followed it. The collection is the last segment once a trailing
--- number is off, so a project holds as many segments as gitlab's groups nest
--- and may itself be named after a collection.
--- @param rest string
--- @return string? host
--- @return string? project
--- @return forge.Collection? collection
--- @return integer? number
--- @return string? query
local function split(rest)
  local body, query = rest:match('^(.-)%?q=(.+)$')
  body = body or rest

  local number
  local shorter, digits = body:match('^(.+)/(%d+)$')
  if shorter then
    body, number = shorter, tonumber(digits)
  end

  local segments = vim.split(body, '/', { plain = true })
  local collection = segments[#segments]
  if #segments < 3 or not COLLECTIONS[collection] then
    return nil
  end
  local project = table.concat(vim.list_slice(segments, 2, #segments - 1), '/')
  local named = collection --[[@as forge.Collection]]
  return segments[1], project, named, number, query
end

--- @param str string
--- @return forge.Uri?
function M.parse(str)
  local rest = str:match('^' .. SCHEME .. '(.+)$')
  if not rest then
    return nil
  end
  local host, project, collection, number, query = split(rest)
  if not host then
    return nil
  end
  return {
    host = host,
    project = project,
    collection = collection,
    number = number,
    query = query and decode(query) or nil,
  }
end

--- What each forge calls a collection inside its own web addresses. github
--- spells a single pull request singular and the list plural; gitlab spells
--- both the same.
local MEMBERS = {
  issues = 'issues',
  pull = 'prs',
  pulls = 'prs',
  merge_requests = 'prs',
  --- gitlab is moving issues to work items, and does it per project: the same
  --- api answers one project with a /-/issues/ url and another with this one.
  work_items = 'issues',
}

--- The target a forge's own web address names.
---
--- gitlab puts `/-/` between a project's path and what follows, which is what
--- makes an arbitrarily nested group path unambiguous. github has no such
--- separator, so a path there is exactly two segments.
--- @param url string
--- @return forge.Target?
function M.web(url)
  local host, rest = url:match('^https?://([%w.-]+)/(.+)$')
  if not host then
    return nil
  end
  rest = rest:gsub('[#?].*$', ''):gsub('/$', '')

  local project, member, number = rest:match('^(.+)/%-/([%a_]+)/(%d+)$')
  if not project then
    project, member = rest:match('^(.+)/%-/([%a_]+)$')
  end
  if not project then
    local owner, repo
    owner, repo, member, number = rest:match('^([^/]+)/([^/]+)/(%a+)/(%d+)$')
    if not owner then
      owner, repo, member = rest:match('^([^/]+)/([^/]+)/(%a+)$')
    end
    project = owner and ('%s/%s'):format(owner, repo) or nil
  end

  if not project or not MEMBERS[member] then
    return nil
  end
  return {
    host = host,
    project = project,
    collection = MEMBERS[member],
    number = tonumber(number),
  }
end

--- Resolve what the user typed into a target. See |:Issue| for the forms.
---
--- A form naming no repository leaves `host` and `project` unset for the CLI
--- to answer, so this never shells out and never fails for want of a remote.
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

  local web = M.web(target)
  if web then
    return web
  end

  --- gitlab numbers merge requests apart from issues and gives them a sigil of
  --- their own, so "!" says which collection it means and the caller's intent
  --- does not come into it.
  local project, number = target:match('^([%w._/-]+)!(%d+)$')
  if project and project:find('/') then
    return { project = project, collection = 'prs', number = tonumber(number) }
  end
  number = target:match('^!(%d+)$')
  if number then
    return { collection = 'prs', number = tonumber(number) }
  end

  project, number = target:match('^([%w._/-]+)#(%d+)$')
  if project and project:find('/') then
    return { project = project, collection = collection, number = tonumber(number) }
  end
  if target:match('^[%w._/-]+$') and target:find('/') then
    return { project = target, collection = collection }
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
