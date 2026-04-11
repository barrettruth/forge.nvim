local M = {}

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

local function remote_url(name)
  local result = vim.system({ 'git', 'remote', 'get-url', name }, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return trim(result.stdout)
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

return M
