local M = {}

local function normalize_url(url)
  if type(url) ~= 'string' then
    return nil
  end
  local normalized = vim.trim(url)
  if normalized == '' then
    return nil
  end
  normalized = normalized:gsub('%.git$', '')
  normalized = normalized:gsub('^ssh://git@', 'https://')
  normalized = normalized:gsub('^git@([^:]+):', 'https://%1/')
  normalized = normalized:gsub('/+$', '')
  normalized = normalized:gsub('#.*$', '')
  normalized = normalized:gsub('%?.*$', '')
  return normalized
end

local function split_url(url)
  local normalized = normalize_url(url)
  if not normalized then
    return nil
  end
  local host, path = normalized:match('^https?://([^/]+)/(.+)$')
  if not host or not path then
    return nil
  end
  return host, path
end

local function github_scope(url)
  local host, path = split_url(url)
  if not host then
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

local function gitlab_scope(url)
  local host, path = split_url(url)
  if not host then
    return nil
  end
  local slug = path:match('^(.-)/%-/') or path
  slug = slug and slug:gsub('/+$', '') or nil
  if not slug or slug == '' then
    return nil
  end
  local repo = slug:match('([^/]+)$')
  local namespace = repo and slug:sub(1, #slug - #repo - 1) or ''
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

local function codeberg_scope(url)
  local host, path = split_url(url)
  if not host then
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

function M.same(a, b)
  local ka = M.key(a)
  local kb = M.key(b)
  return ka ~= '' and ka == kb
end

function M.repo_arg(scope)
  return type(scope) == 'table' and scope.repo_arg or nil
end

function M.web_url(scope)
  return type(scope) == 'table' and scope.web_url or ''
end

function M.git_url(scope)
  local url = M.web_url(scope)
  if url == '' then
    return nil
  end
  return url .. '.git'
end

function M.encode_project(scope)
  if type(scope) ~= 'table' or not scope.slug or scope.slug == '' then
    return nil
  end
  return (scope.slug:gsub('/', '%%2F'))
end

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

function M.remote_ref(scope, branch)
  local remote = M.remote_name(scope)
  if remote and type(branch) == 'string' and branch ~= '' then
    return remote .. '/' .. branch
  end
  return nil
end

return M
