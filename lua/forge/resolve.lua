local M = {}

local scope_mod = require('forge.scope')
local target_mod = require('forge.target')

---@type table<string, string|false>
local gitlab_project_ids = {}

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

---@param message string
---@param code string?
---@return nil, forge.CmdError
local function error_result(message, code)
  return nil, {
    code = code,
    message = message,
  }
end

---@param result forge.SystemResult
---@param fallback string
---@return string
local function cmd_error(result, fallback)
  local msg = trim(result.stderr)
  if not msg then
    msg = trim(result.stdout)
  end
  return msg or fallback
end

---@param opts forge.CurrentPROpts?
---@return forge.Forge?
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

---@param value any
---@return forge.ScopeKind?
local function scope_kind(value)
  local scope = value
  if type(scope) == 'table' and type(scope.scope) == 'table' then
    scope = scope.scope
  elseif type(scope) == 'table' and type(scope.head_scope) == 'table' then
    scope = scope.head_scope
  end
  local kind = type(scope) == 'table' and scope.kind or nil
  if kind == nil or kind == '' or kind == 'repo' then
    return nil
  end
  if type(scope.host) ~= 'string' or type(scope.slug) ~= 'string' then
    return nil
  end
  return kind
end

---@param opts forge.CurrentPROpts?
---@param forge forge.Forge?
---@return forge.ScopeKind?
local function forge_name(opts, forge)
  if type(opts) == 'table' and type(opts.forge_name) == 'string' and opts.forge_name ~= '' then
    return opts.forge_name
  end
  if type(forge) == 'table' and type(forge.name) == 'string' and forge.name ~= '' then
    return forge.name
  end
  if type(opts) ~= 'table' then
    return nil
  end
  for _, value in ipairs({ opts.head_scope, opts.base_scope, opts.scope, opts.repo, opts.head }) do
    local kind = scope_kind(value)
    if kind then
      return kind
    end
  end
  return nil
end

---@param scopes forge.Scope[]
---@param seen table<string, boolean>
---@param value forge.Scope?
local function add_scope(scopes, seen, value)
  local key = scope_mod.key(value)
  if key == '' or seen[key] then
    return
  end
  seen[key] = true
  scopes[#scopes + 1] = value
end

---@param json table
---@param base_scope forge.Scope?
---@return forge.HeadRef
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

---@param json table
---@return forge.HeadRef
local function gitlab_head(json)
  return {
    branch = trim(json.source_branch),
    project_id = json.source_project_id ~= nil and tostring(json.source_project_id) or nil,
  }
end

---@param json table
---@param base_scope forge.Scope?
---@return forge.HeadRef
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

---@param forge forge.Forge
---@param json table
---@param base_scope forge.Scope?
---@return forge.HeadRef
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

---@param scope forge.Scope?
---@return string?, string?
local function gitlab_project_id(scope)
  local slug = type(scope) == 'table' and scope.slug or 'scope'
  local host = type(scope) == 'table' and scope.host or 'gitlab.com'
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
    .system({ 'glab', 'api', '--hostname', host, ('projects/%s'):format(project) }, { text = true })
    :wait()
  if result.code ~= 0 then
    return nil, cmd_error(result, ('failed to resolve GitLab project for %s'):format(slug))
  end
  local ok, json = pcall(vim.json.decode, result.stdout or '{}')
  if not ok or type(json) ~= 'table' or json.id == nil then
    return nil, ('failed to parse GitLab project for %s'):format(slug)
  end
  local id = tostring(json.id)
  gitlab_project_ids[key] = id
  return id
end

---@param forge forge.Forge
---@param expected forge.HeadRef
---@param actual forge.HeadRef
---@return boolean?, string?
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

---@param forge forge.Forge
---@param num string
---@param scope forge.Scope?
---@return table?, string?
local function fetch_pr_json(forge, num, scope)
  local result = vim.system(forge:fetch_pr_details_cmd(num, scope), { text = true }):wait()
  if result.code ~= 0 then
    return nil,
      cmd_error(result, ('failed to fetch %s #%s'):format(forge.labels.pr_one or 'PR', num))
  end
  local ok, json = pcall(vim.json.decode, result.stdout or '{}')
  if not ok or type(json) ~= 'table' then
    return nil, ('failed to parse %s details'):format(forge.labels.pr_one or 'PR')
  end
  return json
end

---@param forge forge.Forge
---@param branch string
---@param scope forge.Scope?
---@return string[]?, string?
local function list_pr_numbers(forge, branch, scope)
  local result = vim.system(forge:pr_for_branch_cmd(branch, scope), { text = true }):wait()
  if result.code ~= 0 then
    return nil, cmd_error(result, ('failed to fetch %s'):format(forge.labels.pr or 'PRs'))
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

---@param head forge.HeadRef
---@return string
local function head_label(head)
  local slug = type(head.scope) == 'table' and head.scope.slug or nil
  if slug and slug ~= '' then
    return ('%s@%s'):format(slug, head.branch)
  end
  return head.branch
end

---@param head forge.HeadLike?
---@param opts forge.CurrentPROpts
---@param kind forge.ScopeKind
---@param parse_opts forge.TargetParseOpts
---@return forge.HeadRef?, string?
local function resolve_head(head, opts, kind, parse_opts)
  local value = head
  if value == nil then
    value = opts.head
  end
  local branch = trim(opts.head_branch)
  local scope, err = target_mod.resolve_scope(opts.head_scope, kind, parse_opts)
  if err then
    return nil, err
  end
  local project_id = trim(opts.project_id)
  if type(value) == 'string' then
    local rev, rev_err = target_mod.parse_rev(value, parse_opts)
    if not rev then
      return nil, rev_err
    end
    branch = branch or trim(rev.rev)
    if not scope then
      scope, err = target_mod.resolve_scope(target_mod.repo_target(rev), kind, parse_opts)
      if err then
        return nil, err
      end
    end
  elseif type(value) == 'table' then
    if value.kind == 'rev' then
      branch = branch or trim(value.rev)
      if not scope then
        scope, err = target_mod.resolve_scope(target_mod.repo_target(value), kind, parse_opts)
        if err then
          return nil, err
        end
      end
    else
      ---@cast value forge.HeadInput
      branch = branch or trim(value.branch or value.head_branch or value.rev)
      project_id = project_id or trim(value.project_id)
      if not scope then
        scope, err = target_mod.resolve_scope(
          value.scope or value.head_scope or target_mod.repo_target(value),
          kind,
          parse_opts
        )
        if err then
          return nil, err
        end
      end
    end
  end
  if not branch then
    branch = target_mod.current_branch()
    if not branch then
      return nil, 'detached HEAD'
    end
  end
  if not scope then
    scope = target_mod.push_scope_for_branch(branch, kind, parse_opts)
  end
  return {
    branch = branch,
    scope = scope,
    project_id = project_id,
  }
end

---@param opts forge.CurrentPROpts
---@param head forge.HeadRef
---@param kind forge.ScopeKind
---@param parse_opts forge.TargetParseOpts
---@return forge.Scope[]?, string?, string?
local function candidate_scopes(opts, head, kind, parse_opts)
  local repo = opts.repo or opts.base_scope or opts.scope
  if repo ~= nil then
    local scope, err = target_mod.resolve_scope(repo, kind, parse_opts)
    if not scope then
      return nil, err, 'invalid_repo'
    end
    return { scope }
  end
  local scopes = {}
  local seen = {}
  add_scope(scopes, seen, target_mod.push_scope_for_branch(head.branch, kind, parse_opts))
  add_scope(scopes, seen, target_mod.repo_scope(target_mod.collaboration_repo(parse_opts), kind))
  return scopes
end

---@param forge forge.Forge
---@param head forge.HeadRef
---@param scope forge.Scope
---@return forge.PRRef[]?, string?
local function matching_prs(forge, head, scope)
  local nums, list_err = list_pr_numbers(forge, head.branch, scope)
  if not nums then
    return nil, list_err
  end
  local matches = {}
  for _, num in ipairs(nums) do
    local json, fetch_err = fetch_pr_json(forge, num, scope)
    if not json then
      return nil, fetch_err
    end
    local exact, match_err = head_matches(forge, head, pr_head(forge, json, scope))
    if match_err then
      return nil, match_err
    end
    if exact then
      matches[#matches + 1] = {
        num = num,
        scope = scope,
      }
    end
  end
  return matches
end

---@param repo forge.RepoLike?
---@param opts forge.CurrentPROpts?
---@return forge.Scope?, forge.CmdError?
function M.repo(repo, opts)
  opts = opts or {}
  local forge = current_forge(opts)
  local kind = forge_name(opts, forge)
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
  local scope, err = target_mod.resolve_scope(value, kind, target_mod.parse_opts(opts))
  if not scope then
    return error_result(err or 'invalid repo address', 'invalid_repo')
  end
  return scope
end

---@param head forge.HeadLike?
---@param opts forge.CurrentPROpts?
---@return forge.HeadRef?, forge.CmdError?
function M.head(head, opts)
  opts = opts or {}
  local forge = current_forge(opts)
  local kind = forge_name(opts, forge)
  if not kind then
    return error_result('no forge detected', 'no_forge')
  end
  local resolved, err = resolve_head(head, opts, kind, target_mod.parse_opts(opts))
  if resolved then
    return resolved
  end
  return error_result(
    err or 'invalid head',
    err == 'detached HEAD' and 'detached_head' or 'invalid_head'
  )
end

---@param opts forge.CurrentPROpts?
---@return forge.PRRef?, forge.CmdError?
function M.current_pr(opts)
  opts = opts or {}
  local forge = current_forge(opts)
  if not forge then
    return error_result('no forge detected', 'no_forge')
  end
  local kind = forge_name(opts, forge)
  if not kind then
    return error_result('no forge detected', 'no_forge')
  end
  local parse_opts = target_mod.parse_opts(opts)
  local head, head_err = resolve_head(opts.head, opts, kind, parse_opts)
  if not head then
    return error_result(
      head_err or 'invalid head',
      head_err == 'detached HEAD' and 'detached_head' or 'invalid_head'
    )
  end
  local repos, repo_err, repo_code = candidate_scopes(opts, head, kind, parse_opts)
  if not repos then
    return error_result(repo_err or 'invalid repo address', repo_code or 'invalid_repo')
  end
  for _, scope in ipairs(repos) do
    local matches, match_err = matching_prs(forge, head, scope)
    if not matches then
      return error_result(match_err or 'current PR lookup failed', 'lookup_failed')
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
