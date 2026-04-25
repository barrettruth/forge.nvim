local M = {}

local default_hosts = {
  github = 'github.com',
  gitlab = 'gitlab.com',
  codeberg = 'codeberg.org',
}

---@param text any
---@return string?
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

---@param url any
---@return string?
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

---@param url any
---@return string?, string?
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

---@param opts table?
---@return table<string, string>
local function alias_map(opts)
  return type(opts) == 'table' and type(opts.aliases) == 'table' and opts.aliases or {}
end

---@param opts table?
---@return boolean
local function has_parse_opts(opts)
  return type(opts) == 'table'
    and (opts.resolve_repo ~= nil or opts.aliases ~= nil or opts.default_repo ~= nil)
end

---@return forge.TargetParseOpts
local function config_parse_opts()
  local ok, forge = pcall(require, 'forge')
  if not ok or type(forge) ~= 'table' or type(forge.config) ~= 'function' then
    return {}
  end
  local cfg = forge.config()
  local targets = type(cfg) == 'table' and cfg.targets or nil
  local aliases = type(targets) == 'table' and targets.aliases or nil
  local default_repo = type(targets) == 'table' and targets.default_repo or nil
  return {
    aliases = type(aliases) == 'table' and aliases or {},
    default_repo = type(default_repo) == 'string' and default_repo or nil,
  }
end

---@param cmd string[]
---@return string?
local function shell_text(cmd)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return trim(result.stdout)
end

---@param name string
---@return string?
local function remote_url(name)
  return shell_text({ 'git', 'remote', 'get-url', name })
end

---@return string?
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

---@param branch string?
---@return string?
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

---@param fragment string?
---@return forge.LineRange?, string?
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

---@param text string
---@return forge.RepoTarget?, string?
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

---@param text string
---@param opts forge.TargetParseOpts?
---@return forge.RepoTarget?, string?
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

---@param opts table?
---@return forge.TargetParseOpts
function M.parse_opts(opts)
  local explicit = type(opts) == 'table' and opts.target_opts or nil
  if type(explicit) == 'table' then
    local parsed = vim.deepcopy(explicit)
    parsed.resolve_repo = true
    return parsed
  end
  if has_parse_opts(opts) then
    local parsed = vim.deepcopy(opts)
    parsed.resolve_repo = true
    return parsed
  end
  local parsed = config_parse_opts()
  parsed.resolve_repo = true
  return parsed
end

---@param value forge.TargetValue|forge.HeadInput|forge.Scope|nil
---@return forge.RepoLike?
function M.repo_target(value)
  if type(value) ~= 'table' then
    return nil
  end
  if value.kind == 'repo' then
    return value
  end
  if value.kind == 'rev' then
    return value.repo
  end
  if value.kind == 'location' and type(value.rev) == 'table' then
    return value.rev.repo
  end
  return value.repo
end

---@param value forge.TargetValue|forge.HeadInput|forge.RepoLike|nil
---@param forge_name forge.ScopeKind
---@param opts table?
---@return forge.Scope?, string?
function M.resolve_scope(value, forge_name, opts)
  local parse_opts = M.parse_opts(opts)
  if
    type(value) == 'table'
    and value.kind ~= 'repo'
    and type(value.host) == 'string'
    and type(value.slug) == 'string'
  then
    ---@cast value forge.Scope
    return value
  end
  if type(value) == 'table' then
    if value.kind == 'repo' then
      return M.repo_scope(value, forge_name)
    end
    local repo = M.repo_target(value)
    if type(repo) == 'table' then
      return M.resolve_scope(repo, forge_name, parse_opts)
    end
  end
  if type(value) == 'string' then
    local repo, err = M.resolve_repo(value, parse_opts)
    if not repo then
      return nil, err
    end
    return M.repo_scope(repo, forge_name)
  end
  return nil
end

---@return string?
function M.current_branch()
  return shell_text({ 'git', 'branch', '--show-current' })
end

---@param opts table?
---@return forge.RepoTarget?
function M.current_repo(opts)
  local remote = preferred_remote_name()
  if not remote then
    return nil
  end
  return M.resolve_repo(remote, M.parse_opts(opts))
end

---@param branch string?
---@param opts table?
---@return forge.RepoTarget?
function M.push_repo_for_branch(branch, opts)
  local remote = push_remote_name(branch)
  if not remote then
    return nil
  end
  return M.resolve_repo(remote, M.parse_opts(opts))
end

---@param opts table?
---@return forge.RepoTarget?
function M.push_repo(opts)
  return M.push_repo_for_branch(M.current_branch(), opts)
end

---@param opts table?
---@return forge.RepoTarget?
function M.collaboration_repo(opts)
  local parse_opts = M.parse_opts(opts)
  local configured = type(parse_opts) == 'table' and trim(parse_opts.default_repo) or nil
  if configured then
    local resolved = M.resolve_repo(configured, parse_opts)
    if resolved then
      return resolved
    end
  end
  for _, remote in ipairs({ 'upstream', 'origin' }) do
    local resolved = M.resolve_repo(remote, parse_opts)
    if resolved then
      return resolved
    end
  end
  return nil
end

---@param branch string?
---@param repo forge.RepoTarget?
---@return forge.RevTarget?
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

---@param repo forge.RepoTarget?
---@return forge.RevTarget?
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

---@param opts table?
---@return forge.RevTarget?
function M.current_rev(opts)
  return M.branch_rev(M.current_branch(), M.current_repo(opts))
end

---@param branch string?
---@param forge_name forge.ScopeKind
---@param opts table?
---@return forge.Scope?
function M.push_scope_for_branch(branch, forge_name, opts)
  return M.repo_scope(M.push_repo_for_branch(branch, opts), forge_name)
end

---@param branch string?
---@param opts table?
---@return forge.RevTarget?
function M.push_rev_for_branch(branch, opts)
  return M.branch_rev(branch, M.push_repo_for_branch(branch, opts))
end

---@param opts table?
---@return forge.RevTarget?
function M.push_rev(opts)
  return M.push_rev_for_branch(M.current_branch(), opts)
end

---@param opts table?
---@return forge.RevTarget?
function M.collaboration_default_branch(opts)
  return M.default_branch_rev(M.collaboration_repo(opts))
end

---@param text string
---@param opts forge.TargetParseOpts?
---@return forge.RevTarget?, string?
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

---@param text any
---@param label string
---@return string?, string?
local function parse_bare_ref(text, label)
  local value = trim(text)
  if not value then
    return nil, 'empty ' .. label
  end
  if value:find(':', 1, true) or value:find('#', 1, true) then
    return nil, 'invalid ' .. label .. ': ' .. value
  end
  if value ~= '@' and value:sub(1, 1) == '@' and value:sub(1, 2) ~= '@{' then
    return nil, 'invalid ' .. label .. ': ' .. value
  end
  if value:find('@', 2, true) then
    return nil, 'invalid ' .. label .. ': ' .. value
  end
  return value
end

---@param text string
---@return forge.BranchTarget?, string?
function M.parse_branch(text)
  local value, err = parse_bare_ref(text, 'branch')
  if not value then
    return nil, err
  end
  return {
    kind = 'branch',
    text = value,
    branch = value,
  }
end

---@param text string
---@return forge.CommitTarget?, string?
function M.parse_commit(text)
  local value, err = parse_bare_ref(text, 'commit')
  if not value then
    return nil, err
  end
  return {
    kind = 'commit',
    text = value,
    commit = value,
  }
end

---@param text string
---@param opts forge.TargetParseOpts?
---@return forge.LocationTarget?, string?
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

---@param repo forge.RepoTarget?
---@param forge_name forge.ScopeKind
---@return forge.Scope?
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
