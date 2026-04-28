local M = {}
local url_mod = require('forge.url')

local SUBJECT_PATHS = {
  github = {
    pr = '/pull/',
    issue = '/issues/',
  },
  gitlab = {
    pr = '/-/merge_requests/',
    issue = '/-/issues/',
  },
  codeberg = {
    pr = '/pulls/',
    issue = '/issues/',
  },
}

local BRANCH_PATHS = {
  github = '/tree/',
  gitlab = '/-/tree/',
  codeberg = '/src/branch/',
}

---@param url string
---@return forge.Scope?
local function github_scope(url)
  local host, path = url_mod.split(url)
  if not host or not path then
    return nil
  end
  local owner, repo = path:match('^([^/]+)/([^/]+)')
  if not owner or not repo then
    return nil
  end
  local slug = owner .. '/' .. repo
  local repo_arg = host ~= 'github.com' and (host .. '/' .. slug) or slug
  return {
    kind = 'github',
    host = host,
    owner = owner,
    repo = repo,
    slug = slug,
    repo_arg = repo_arg,
    web_url = ('https://%s/%s'):format(host, slug),
  }
end

---@param url string
---@return forge.Scope?
local function gitlab_scope(url)
  local host, path = url_mod.split(url)
  if not host or not path then
    return nil
  end
  local slug = path
  if not slug or slug == '' then
    return nil
  end
  local repo = slug:match('([^/]+)$')
  if not repo then
    return nil
  end
  local namespace = slug:sub(1, #slug - #repo - 1)
  return {
    kind = 'gitlab',
    host = host,
    namespace = namespace,
    repo = repo,
    slug = slug,
    repo_arg = ('https://%s/%s'):format(host, slug),
    web_url = ('https://%s/%s'):format(host, slug),
  }
end

---@param url string
---@return forge.Scope?
local function codeberg_scope(url)
  local host, path = url_mod.split(url)
  if not host or not path then
    return nil
  end
  local owner, repo = path:match('^([^/]+)/([^/]+)')
  if not owner or not repo then
    return nil
  end
  local slug = owner .. '/' .. repo
  return {
    kind = 'codeberg',
    host = host,
    owner = owner,
    repo = repo,
    slug = slug,
    repo_arg = slug,
    web_url = ('https://%s/%s'):format(host, slug),
  }
end

---@param kind forge.ScopeKind
---@param url string
---@return forge.Scope?
function M.from_url(kind, url)
  if kind == 'github' then
    return github_scope(url)
  end
  if kind == 'gitlab' then
    return gitlab_scope(url)
  end
  if kind == 'codeberg' then
    return codeberg_scope(url)
  end
  return nil
end

---@param scope forge.Scope?
---@return string
function M.key(scope)
  if type(scope) ~= 'table' then
    return ''
  end
  return table.concat({
    scope.kind or '',
    scope.host or '',
    scope.slug or '',
  }, '|')
end

---@param scope forge.Scope?
---@return string?
function M.bufpath(scope)
  if type(scope) ~= 'table' then
    return nil
  end
  local host = scope.host
  local slug = scope.slug
  if type(host) ~= 'string' or host == '' then
    return nil
  end
  if type(slug) ~= 'string' or slug == '' then
    return nil
  end
  return host .. '/' .. slug
end

---@param a forge.Scope?
---@param b forge.Scope?
---@return boolean
function M.same(a, b)
  local ka = M.key(a)
  local kb = M.key(b)
  return ka ~= '' and ka == kb
end

---@param scope forge.Scope?
---@return string?
function M.repo_arg(scope)
  return type(scope) == 'table' and scope.repo_arg or nil
end

---@param scope forge.Scope?
---@return string
function M.web_url(scope)
  return type(scope) == 'table' and scope.web_url or ''
end

---@param scope forge.Scope?
---@return string
function M.resolved_web_url(scope)
  local url = M.web_url(scope)
  if url ~= '' then
    return url
  end
  if type(scope) ~= 'table' then
    return ''
  end
  local host = scope.host
  local slug = scope.slug
  if type(host) ~= 'string' or host == '' or type(slug) ~= 'string' or slug == '' then
    return ''
  end
  return ('https://%s/%s'):format(host, slug)
end

---@param scope forge.Scope?
---@param branch string?
---@return string
function M.branch_web_url(scope, branch)
  if type(branch) ~= 'string' or branch == '' or type(scope) ~= 'table' then
    return ''
  end
  local base = M.resolved_web_url(scope)
  if base == '' then
    return ''
  end
  local path = BRANCH_PATHS[scope.kind]
  if not path then
    return ''
  end
  return base .. path .. branch
end

---@param kind forge.SubjectKind
---@param num string?
---@param scope forge.Scope?
---@return string
function M.subject_web_url(kind, num, scope)
  if type(num) ~= 'string' or num == '' or type(scope) ~= 'table' then
    return ''
  end
  local base = M.resolved_web_url(scope)
  if base == '' then
    return ''
  end
  local paths = SUBJECT_PATHS[scope.kind]
  local path = paths and paths[kind]
  if not path then
    return ''
  end
  return base .. path .. num
end

---@param scope forge.Scope?
---@return string?
function M.git_url(scope)
  local url = M.resolved_web_url(scope)
  if url == '' then
    return nil
  end
  return url .. '.git'
end

---@param scope forge.Scope?
---@return string?
function M.encode_project(scope)
  if type(scope) ~= 'table' or not scope.slug or scope.slug == '' then
    return nil
  end
  return (scope.slug:gsub('/', '%%2F'))
end

---@param scope forge.Scope?
---@return string?
function M.remote_name(scope)
  if type(scope) ~= 'table' then
    return nil
  end
  local result = vim.system({ 'git', 'remote' }, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  for _, remote in ipairs(vim.split(result.stdout or '', '\n', { plain = true, trimempty = true })) do
    local remote_result = vim.system({ 'git', 'remote', 'get-url', remote }, { text = true }):wait()
    if remote_result.code == 0 then
      local other = M.from_url(scope.kind, remote_result.stdout or '')
      if M.same(scope, other) then
        return remote
      end
    end
  end
  return nil
end

---@param scope forge.Scope?
---@param branch string
---@return string?
function M.remote_ref(scope, branch)
  local remote = M.remote_name(scope)
  if remote and branch ~= '' then
    return remote .. '/' .. branch
  end
  return nil
end

return M
