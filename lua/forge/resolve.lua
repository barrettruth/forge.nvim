local M = {}

local scope_mod = require('forge.scope')
local target_mod = require('forge.target')

local gitlab_project_ids = {}

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

local function error_result(message, code)
  return nil, {
    code = code,
    message = message,
  }
end

local function cmd_error(result, fallback)
  local msg = trim(result.stderr)
  if not msg then
    msg = trim(result.stdout)
  end
  return msg or fallback
end

local function repo_target(value)
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

local function current_forge(opts)
  if type(opts) == 'table' and type(opts.forge) == 'table' then
    return opts.forge
  end
  local ok, forge = pcall(require, 'forge')
  if not ok or type(forge) ~= 'table' or type(forge.detect) ~= 'function' then
    return nil
  end
  return forge.detect()
end

local function forge_name(opts)
  if type(opts) == 'table' then
    if type(opts.forge_name) == 'string' and opts.forge_name ~= '' then
      return opts.forge_name
    end
    if
      type(opts.forge) == 'table'
      and type(opts.forge.name) == 'string'
      and opts.forge.name ~= ''
    then
      return opts.forge.name
    end
    for _, value in ipairs({
      opts.head_scope,
      opts.base_scope,
      opts.scope,
      type(opts.repo) == 'table' and opts.repo or nil,
    }) do
      if
        type(value) == 'table'
        and value.kind ~= 'repo'
        and type(value.kind) == 'string'
        and value.kind ~= ''
      then
        return value.kind
      end
    end
    local head = type(opts.head) == 'table' and (opts.head.scope or opts.head.head_scope) or nil
    if type(head) == 'table' and type(head.kind) == 'string' and head.kind ~= '' then
      return head.kind
    end
  end
  local f = current_forge(opts)
  return f and f.name or nil
end

local function target_parse_opts(opts)
  local explicit = type(opts) == 'table' and opts.target_opts or nil
  if type(explicit) == 'table' then
    local parsed = vim.deepcopy(explicit)
    parsed.resolve_repo = true
    return parsed
  end
  local ok, forge = pcall(require, 'forge')
  if not ok or type(forge) ~= 'table' or type(forge.config) ~= 'function' then
    return {
      resolve_repo = true,
    }
  end
  local cfg = forge.config()
  local targets = type(cfg) == 'table' and cfg.targets or nil
  local aliases = type(targets) == 'table' and targets.aliases or nil
  local default_repo = type(targets) == 'table' and targets.default_repo or nil
  return {
    resolve_repo = true,
    aliases = type(aliases) == 'table' and aliases or {},
    default_repo = type(default_repo) == 'string' and default_repo or nil,
  }
end

local function resolve_scope(value, kind, parse_opts)
  if
    type(value) == 'table'
    and value.kind ~= 'repo'
    and type(value.host) == 'string'
    and type(value.slug) == 'string'
  then
    return value
  end
  if type(value) == 'table' and value.kind == 'repo' then
    return target_mod.repo_scope(value, kind)
  end
  if type(value) == 'string' then
    local repo, err = target_mod.resolve_repo(value, parse_opts)
    if not repo then
      return nil, err
    end
    return target_mod.repo_scope(repo, kind)
  end
  return nil
end

local function add_scope(scopes, seen, value)
  local key = scope_mod.key(value)
  if key == '' or seen[key] then
    return
  end
  seen[key] = true
  scopes[#scopes + 1] = value
end

local function github_head(json, base_scope)
  local branch = trim(json.headRefName)
  local owner = type(json.headRepositoryOwner) == 'table'
      and trim(json.headRepositoryOwner.login or json.headRepositoryOwner.name)
    or nil
  local repo = type(json.headRepository) == 'table' and trim(json.headRepository.name) or nil
  local full_name = type(json.headRepository) == 'table' and trim(json.headRepository.nameWithOwner)
    or nil
  if not owner and full_name then
    owner = full_name:match('^([^/]+)/')
  end
  if not repo and full_name then
    repo = full_name:match('/([^/]+)$')
  end
  local scope = nil
  if owner and repo then
    local host = type(base_scope) == 'table' and base_scope.host or 'github.com'
    scope = scope_mod.from_url('github', ('https://%s/%s/%s'):format(host, owner, repo))
  end
  return {
    branch = branch,
    scope = scope,
  }
end

local function gitlab_head(json)
  return {
    branch = trim(json.source_branch),
    project_id = json.source_project_id ~= nil and tostring(json.source_project_id) or nil,
  }
end

local function codeberg_head(json, base_scope)
  local head = type(json.head) == 'table' and json.head or nil
  local branch = trim(head and (head.ref or head.name) or json.head)
  local repo = head and type(head.repo) == 'table' and head.repo or nil
  local full_name = trim(repo and (repo.full_name or repo.fullName))
  local scope = nil
  if full_name then
    local host = type(base_scope) == 'table' and base_scope.host or 'codeberg.org'
    scope = scope_mod.from_url('codeberg', ('https://%s/%s'):format(host, full_name))
  end
  return {
    branch = branch,
    scope = scope,
  }
end

local function pr_head(forge, json, base_scope)
  if forge.name == 'github' then
    return github_head(json, base_scope)
  end
  if forge.name == 'gitlab' then
    return gitlab_head(json)
  end
  if forge.name == 'codeberg' then
    return codeberg_head(json, base_scope)
  end
  return {
    branch = trim(json.headRefName or json.source_branch),
    scope = nil,
  }
end

local function gitlab_project_id(scope)
  local key = scope_mod.key(scope)
  if key == '' then
    return nil
  end
  if gitlab_project_ids[key] ~= nil then
    return gitlab_project_ids[key] or nil
  end
  local project = scope_mod.encode_project(scope)
  if not project then
    gitlab_project_ids[key] = false
    return nil
  end
  local result = vim
    .system(
      { 'glab', 'api', '--hostname', scope.host or 'gitlab.com', ('projects/%s'):format(project) },
      { text = true }
    )
    :wait()
  if result.code ~= 0 then
    return nil,
      cmd_error(result, ('failed to resolve GitLab project for %s'):format(scope.slug or 'scope'))
  end
  local ok, json = pcall(vim.json.decode, result.stdout or '{}')
  if not ok or type(json) ~= 'table' or json.id == nil then
    return nil, ('failed to parse GitLab project for %s'):format(scope.slug or 'scope')
  end
  local id = tostring(json.id)
  gitlab_project_ids[key] = id
  return id
end

local function head_matches(forge, expected, actual)
  if trim(actual.branch) ~= expected.branch then
    return false
  end
  if forge.name == 'gitlab' then
    local expected_id = expected.project_id
    local err
    if not expected_id and expected.scope then
      expected_id, err = gitlab_project_id(expected.scope)
      if err then
        return nil, err
      end
    end
    local actual_id = trim(actual.project_id)
    return expected_id ~= nil and actual_id ~= nil and expected_id == actual_id
  end
  return scope_mod.same(expected.scope, actual.scope)
end

local function fetch_pr_json(forge, num, scope)
  local result = vim.system(forge:fetch_pr_details_cmd(num, scope), { text = true }):wait()
  if result.code ~= 0 then
    return nil,
      cmd_error(result, ('failed to fetch %s #%s'):format(forge.labels.pr_one or 'PR', num))
  end
  local ok, json = pcall(vim.json.decode, result.stdout or '{}')
  if not ok or type(json) ~= 'table' then
    return nil, ('failed to parse %s #%s details'):format(forge.labels.pr_one or 'PR', num)
  end
  return json
end

local function list_pr_numbers(forge, branch, scope)
  local result = vim.system(forge:pr_for_branch_cmd(branch, scope), { text = true }):wait()
  if result.code ~= 0 then
    return nil,
      cmd_error(result, ('failed to list %s for %s'):format(forge.labels.pr_full or 'PRs', branch))
  end
  local nums = {}
  local seen = {}
  for _, line in ipairs(vim.split(result.stdout or '', '\n', { plain = true, trimempty = true })) do
    local num = trim(line)
    if num and num ~= 'null' and not seen[num] then
      seen[num] = true
      nums[#nums + 1] = num
    end
  end
  return nums
end

local function head_label(head)
  local slug = type(head.scope) == 'table' and head.scope.slug or nil
  if slug and slug ~= '' then
    return ('%s@%s'):format(slug, head.branch)
  end
  return head.branch
end

function M.repo(repo, opts)
  opts = opts or {}
  local kind = forge_name(opts)
  if not kind then
    return error_result('no forge detected', 'no_forge')
  end
  local value = repo
  if value == nil then
    value = opts.repo or opts.base_scope or opts.scope
  end
  if value == nil then
    return nil
  end
  local scope, err = resolve_scope(value, kind, target_parse_opts(opts))
  if not scope then
    return error_result(err or 'invalid repo address', 'invalid_repo')
  end
  return scope
end

function M.head(head, opts)
  opts = opts or {}
  local kind = forge_name(opts)
  if not kind then
    return error_result('no forge detected', 'no_forge')
  end
  local parse_opts = target_parse_opts(opts)
  local value = head
  if value == nil then
    value = opts.head
  end
  local branch = trim(opts.head_branch)
  local scope, err = resolve_scope(opts.head_scope, kind, parse_opts)
  if err then
    return error_result(err, 'invalid_head')
  end
  local project_id = trim(opts.project_id)
  if type(value) == 'string' then
    local rev
    rev, err = target_mod.parse_rev(value, parse_opts)
    if not rev then
      return error_result(err, 'invalid_head')
    end
    branch = branch or trim(rev.rev)
    if not scope then
      scope, err = resolve_scope(repo_target(rev), kind, parse_opts)
      if err then
        return error_result(err, 'invalid_head')
      end
    end
  elseif type(value) == 'table' then
    if value.kind == 'rev' then
      branch = branch or trim(value.rev)
      if not scope then
        scope, err = resolve_scope(repo_target(value), kind, parse_opts)
        if err then
          return error_result(err, 'invalid_head')
        end
      end
    else
      branch = branch or trim(value.branch or value.head_branch or value.rev)
      project_id = project_id or trim(value.project_id)
      if not scope then
        scope, err = resolve_scope(value.scope or value.head_scope or value.repo, kind, parse_opts)
        if err then
          return error_result(err, 'invalid_head')
        end
      end
    end
  end
  if not branch then
    local current = target_mod.push_rev(parse_opts)
    branch = current and trim(current.rev) or nil
    if not branch then
      return error_result('detached HEAD', 'detached_head')
    end
    if not scope then
      scope = target_mod.repo_scope(repo_target(current), kind)
    end
  end
  if not scope then
    scope = target_mod.repo_scope(target_mod.push_repo(parse_opts), kind)
  end
  return {
    branch = branch,
    scope = scope,
    project_id = project_id,
  }
end

function M.current_pr(opts)
  opts = opts or {}
  local forge = current_forge(opts)
  if not forge then
    return error_result('no forge detected', 'no_forge')
  end
  local kind = forge.name or forge_name(opts)
  if not kind then
    return error_result('no forge detected', 'no_forge')
  end
  local parse_opts = target_parse_opts(opts)
  local repo = opts.repo or opts.base_scope or opts.scope
  local repos = nil
  if repo ~= nil then
    local resolved, err = resolve_scope(repo, kind, parse_opts)
    if not resolved then
      return error_result(err or 'invalid repo address', 'invalid_repo')
    end
    repos = { resolved }
  else
    local seen = {}
    repos = {}
    add_scope(repos, seen, target_mod.repo_scope(target_mod.push_repo(parse_opts), kind))
    add_scope(repos, seen, target_mod.repo_scope(target_mod.collaboration_repo(parse_opts), kind))
  end
  local head, err = M.head(
    opts.head,
    vim.tbl_extend('force', opts, {
      forge = forge,
      forge_name = kind,
      target_opts = parse_opts,
    })
  )
  if not head then
    return nil, err
  end
  for _, scope in ipairs(repos) do
    local nums, list_err = list_pr_numbers(forge, head.branch, scope)
    if not nums then
      return error_result(list_err, 'lookup_failed')
    end
    local matches = {}
    for _, num in ipairs(nums) do
      local json, fetch_err = fetch_pr_json(forge, num, scope)
      if not json then
        return error_result(fetch_err, 'lookup_failed')
      end
      local exact, match_err = head_matches(forge, head, pr_head(forge, json, scope))
      if match_err then
        return error_result(match_err, 'lookup_failed')
      end
      if exact then
        matches[#matches + 1] = {
          num = num,
          scope = scope,
        }
      end
    end
    if #matches == 1 then
      return matches[1]
    end
    if #matches > 1 then
      return error_result(
        ('multiple %s match head %s; pass repo= or head='):format(
          forge.labels.pr_full or 'PRs',
          head_label(head)
        ),
        'ambiguous_pr'
      )
    end
  end
  return nil
end

return M
