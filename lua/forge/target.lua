local M = {}

local default_hosts = {
  github = 'github.com',
  gitlab = 'gitlab.com',
  codeberg = 'codeberg.org',
}

local function trim(text)
  if type(text) ~= 'string' then
    return nil
  end
  local value = vim.trim(text)
  if value == '' then
    return nil
  end
  return value
end

local function normalize_url(url)
  local value = trim(url)
  if not value then
    return nil
  end
  local normalized = tostring(value)
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
  path = path:match('^(.-)/%-/') or path
  path = path:gsub('/+$', '')
  if path == '' then
    return nil
  end
  return host, path
end

local function alias_map(opts)
  return type(opts) == 'table' and type(opts.aliases) == 'table' and opts.aliases or {}
end

local function shell_text(cmd)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return trim(result.stdout)
end

local function remote_url(name)
  return shell_text({ 'git', 'remote', 'get-url', name })
end

local function preferred_remote_name()
  if remote_url('origin') then
    return 'origin'
  end
  local remotes = shell_text({ 'git', 'remote' })
  if not remotes then
    return nil
  end
  return vim.split(remotes, '\n', { plain = true, trimempty = true })[1]
end

local function push_remote_name(branch)
  local value = trim(branch)
  if not value then
    return preferred_remote_name()
  end
  local branch_remote = shell_text({ 'git', 'config', 'branch.' .. value .. '.pushRemote' })
  if branch_remote then
    return branch_remote
  end
  local push_default = shell_text({ 'git', 'config', 'remote.pushDefault' })
  if push_default then
    return push_default
  end
  local upstream = shell_text({ 'git', 'rev-parse', '--abbrev-ref', value .. '@{upstream}' })
  if upstream then
    local remote = upstream:match('^([^/]+)/')
    if remote then
      return remote
    end
  end
  return preferred_remote_name()
end

local function parse_range(fragment)
  if fragment == nil then
    return nil
  end
  local line = fragment:match('^L(%d+)$')
  if line then
    local value = tonumber(line)
    return {
      start_line = value,
      end_line = value,
    }
  end
  local start_line, end_line = fragment:match('^L(%d+)%-L(%d+)$')
  if start_line and end_line then
    return {
      start_line = tonumber(start_line),
      end_line = tonumber(end_line),
    }
  end
  return nil, 'invalid range: ' .. fragment
end

function M.parse_repo(text)
  local value = trim(text)
  if not value then
    return nil, 'empty repo address'
  end
  if value:find('@', 1, true) or value:find(':', 1, true) or value:find('#', 1, true) then
    return nil, 'invalid repo address: ' .. value
  end

  local hosted = value
  if value:match('^[^/]+%.[^/]+/.+$') then
    hosted = 'https://' .. value
  end
  local host, slug = split_url(hosted)
  if host and slug then
    return {
      kind = 'repo',
      form = 'hosted',
      text = value,
      host = host,
      slug = slug,
    }
  end

  if value:match('^[^/%s]+/[^%s]+$') then
    return {
      kind = 'repo',
      form = 'path',
      text = value,
      slug = value,
    }
  end

  if value:match('^[%w_.%-]+$') then
    return {
      kind = 'repo',
      form = 'symbolic',
      text = value,
      name = value,
    }
  end

  return nil, 'invalid repo address: ' .. value
end

function M.resolve_repo(text, opts)
  local value = trim(text)
  if not value then
    return nil, 'empty repo address'
  end

  local aliases = alias_map(opts)
  local alias_target = aliases[value]
  if type(alias_target) == 'string' and alias_target ~= '' then
    local remote = alias_target:match('^remote:(.+)$')
    if remote then
      local resolved, err = M.resolve_repo(remote, {
        aliases = {},
      })
      if not resolved then
        return nil, err
      end
      resolved.via = 'alias'
      resolved.alias = value
      return resolved
    end
    local resolved, err = M.parse_repo(alias_target)
    if not resolved then
      return nil, err
    end
    resolved.via = 'alias'
    resolved.alias = value
    return resolved
  end

  local remote = remote_url(value)
  if remote then
    local host, slug = split_url(remote)
    if not host or not slug then
      return nil, 'invalid remote address: ' .. value
    end
    return {
      kind = 'repo',
      form = 'hosted',
      text = value,
      host = host,
      slug = slug,
      via = 'remote',
      remote = value,
    }
  end

  local parsed, err = M.parse_repo(value)
  if not parsed then
    return nil, err
  end
  if parsed.form == 'symbolic' then
    return nil, 'unresolved repo address: ' .. value
  end
  parsed.via = 'explicit'
  return parsed
end

function M.current_branch()
  return shell_text({ 'git', 'branch', '--show-current' })
end

function M.current_repo(opts)
  local remote = preferred_remote_name()
  if not remote then
    return nil
  end
  return M.resolve_repo(remote, opts)
end

function M.push_repo(opts)
  local branch = M.current_branch()
  local remote = push_remote_name(branch)
  if not remote then
    return nil
  end
  return M.resolve_repo(remote, opts)
end

function M.collaboration_repo(opts)
  local configured = type(opts) == 'table' and trim(opts.default_repo) or nil
  if configured then
    local resolved = M.resolve_repo(configured, opts)
    if resolved then
      return resolved
    end
  end
  for _, remote in ipairs({ 'upstream', 'origin' }) do
    local resolved = M.resolve_repo(remote, opts)
    if resolved then
      return resolved
    end
  end
  return nil
end

function M.branch_rev(branch, repo)
  local value = trim(branch)
  if not value then
    return nil
  end
  local rev = {
    kind = 'rev',
    text = '@' .. value,
    rev = value,
  }
  if repo then
    rev.repo = repo
  end
  return rev
end

function M.default_branch_rev(repo)
  if not repo then
    return nil
  end
  return {
    kind = 'rev',
    text = '',
    repo = repo,
    default_branch = true,
  }
end

function M.current_rev(opts)
  return M.branch_rev(M.current_branch(), M.current_repo(opts))
end

function M.push_rev(opts)
  return M.branch_rev(M.current_branch(), M.push_repo(opts))
end

function M.collaboration_default_branch(opts)
  return M.default_branch_rev(M.collaboration_repo(opts))
end

function M.parse_rev(text, opts)
  local value = trim(text)
  if not value then
    return nil, 'empty revision address'
  end
  if value:find(':', 1, true) or value:find('#', 1, true) then
    return nil, 'invalid revision address: ' .. value
  end

  local repo_text
  local rev
  if value:sub(1, 1) == '@' then
    rev = value:sub(2)
  else
    repo_text, rev = value:match('^(.-)@(.+)$')
  end

  if not rev or rev == '' then
    return nil, 'invalid revision address: ' .. value
  end

  local parsed = {
    kind = 'rev',
    text = value,
    rev = rev,
  }

  if repo_text and repo_text ~= '' then
    local repo
    local err
    if opts and opts.resolve_repo then
      repo, err = M.resolve_repo(repo_text, opts)
    else
      repo, err = M.parse_repo(repo_text)
    end
    if not repo then
      return nil, err
    end
    parsed.repo = repo
  end

  return parsed
end

function M.parse_browse_rev(text)
  local value = trim(text)
  if not value then
    return nil, 'empty revision'
  end
  if value:find(':', 1, true) or value:find('#', 1, true) then
    return nil, 'invalid revision: ' .. value
  end
  if value ~= '@' and value:sub(1, 1) == '@' and value:sub(1, 2) ~= '@{' then
    return nil, 'invalid revision: ' .. value
  end
  if value:find('@', 2, true) then
    return nil, 'invalid revision: ' .. value
  end
  return {
    kind = 'rev',
    text = value,
    rev = value,
  }
end

function M.parse_location(text, opts)
  local value = trim(text)
  if not value then
    return nil, 'empty location address'
  end

  local body = value
  local fragment = nil
  local hash = value:find('#', 1, true)
  if hash then
    body = value:sub(1, hash - 1)
    fragment = value:sub(hash + 1)
  end

  local prefix, path = body:match('^(.-):(.+)$')
  if not prefix or not path or path == '' then
    return nil, 'invalid location address: ' .. value
  end

  local rev, err = M.parse_rev(prefix, opts)
  if not rev then
    return nil, err
  end

  local range = nil
  if fragment then
    range, err = parse_range(fragment)
    if not range then
      return nil, err
    end
  end

  return {
    kind = 'location',
    text = value,
    rev = rev,
    path = path,
    range = range,
  }
end

function M.repo_scope(repo, forge_name)
  if type(repo) ~= 'table' then
    return nil
  end
  local host = repo.host
  local slug = repo.slug
  if repo.form == 'path' then
    local current = nil
    local ok, forge = pcall(require, 'forge')
    if ok and type(forge) == 'table' and type(forge.current_scope) == 'function' then
      current = forge.current_scope(forge_name)
    end
    host = current and current.host or default_hosts[forge_name]
  end
  if not host or not slug then
    return nil
  end
  return require('forge.scope').from_url(forge_name, ('https://%s/%s'):format(host, slug))
end

return M
