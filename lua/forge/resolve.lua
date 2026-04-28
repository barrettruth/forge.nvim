local M = {}

local detect_mod = require('forge.detect')
local scope_mod = require('forge.scope')
local system_mod = require('forge.system')
local target_mod = require('forge.target')

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

---@param callback fun(...)
local function schedule_callback(callback, ...)
  local count = select('#', ...)
  local first, second, third, fourth = ...
  vim.schedule(function()
    if count == 0 then
      callback()
      return
    end
    if count == 1 then
      callback(first)
      return
    end
    if count == 2 then
      callback(first, second)
      return
    end
    if count == 3 then
      callback(first, second, third)
      return
    end
    callback(first, second, third, fourth)
  end)
end

---@return forge.Forge?
local function current_forge(opts)
  if type(opts) == 'table' and type(opts.forge) == 'table' then
    return opts.forge
  end
  return detect_mod.detect()
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

---Dispatch to the active backend's `parse_pr_head`. Falls back to a
---universal-best-effort head when a custom backend doesn't implement it.
---@param forge forge.Forge
---@param json table
---@param base_scope forge.Scope?
---@return forge.HeadRef
local function pr_head(forge, json, base_scope)
  if type(forge.parse_pr_head) == 'function' then
    return forge:parse_pr_head(json, base_scope)
  end
  return {
    branch = trim(json.headRefName or json.source_branch),
    scope = nil,
  }
end

---Dispatch to the active backend's `match_head`. Falls back to scope-only
---comparison when a custom backend doesn't implement it.
---@param forge forge.Forge
---@param expected forge.HeadRef
---@param actual forge.HeadRef
---@return boolean?, string?
local function head_matches(forge, expected, actual)
  if type(forge.match_head) == 'function' then
    return forge:match_head(expected, actual)
  end
  if trim(actual.branch) ~= expected.branch then
    return false
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
      system_mod.cmd_error(
        result,
        ('failed to fetch %s #%s'):format(forge.labels.pr_one or 'PR', num)
      )
  end
  local ok, json = pcall(vim.json.decode, result.stdout or '{}')
  if not ok or type(json) ~= 'table' then
    return nil, ('failed to parse %s details'):format(forge.labels.pr_one or 'PR')
  end
  return json
end

---@param value any
---@return forge.PRLookupState?
local function pr_lookup_state_name(value)
  local state = trim(value)
  if not state then
    return nil
  end
  state = state:lower()
  if state == 'open' or state == 'opened' then
    return 'open'
  end
  if state == 'closed' then
    return 'closed'
  end
  if state == 'merged' then
    return 'merged'
  end
  return nil
end

---@param json table
---@return forge.PRLookupState?
local function pr_lookup_state(json)
  if json.merged == true then
    return 'merged'
  end
  local pull_request = type(json.pull_request) == 'table' and json.pull_request or nil
  if pull_request and pull_request.merged == true then
    return 'merged'
  end
  if trim(json.mergedAt or json.merged_at) then
    return 'merged'
  end
  return pr_lookup_state_name(json.state)
end

---@param states forge.PRLookupState[]
---@param value forge.PRLookupState?
---@return boolean
local function lookup_states_include(states, value)
  if not value then
    return false
  end
  for _, state in ipairs(states) do
    if state == value then
      return true
    end
  end
  return false
end

---@param forge forge.Forge
---@param states forge.PRLookupState[]
---@return forge.PRListState[]
local function branch_lookup_states(forge, states)
  local list_states = {}
  local seen = {}
  for _, value in ipairs(states) do
    local state = pr_lookup_state_name(value)
    if state then
      local list_state = state
      if state == 'merged' and forge.name == 'codeberg' then
        list_state = 'closed'
      end
      if not seen[list_state] then
        seen[list_state] = true
        list_states[#list_states + 1] = list_state
      end
    end
  end
  return list_states
end

---@param forge forge.Forge
---@param num string
---@param scope forge.Scope?
---@param callback fun(json: table?, err: string?)
local function fetch_pr_json_async(forge, num, scope, callback)
  vim.system(forge:fetch_pr_details_cmd(num, scope), { text = true }, function(result)
    if result.code ~= 0 then
      schedule_callback(
        callback,
        nil,
        system_mod.cmd_error(
          result,
          ('failed to fetch %s #%s'):format(forge.labels.pr_one or 'PR', num)
        )
      )
      return
    end
    local ok, json = pcall(vim.json.decode, result.stdout or '{}')
    if not ok or type(json) ~= 'table' then
      schedule_callback(
        callback,
        nil,
        ('failed to parse %s details'):format(forge.labels.pr_one or 'PR')
      )
      return
    end
    schedule_callback(callback, json)
  end)
end

---@param forge forge.Forge
---@param branch string
---@param scope forge.Scope?
---@param states forge.PRLookupState[]
---@return string[]?, string?
local function list_pr_numbers(forge, branch, scope, states)
  local nums = {}
  local seen = {}
  for _, list_state in ipairs(branch_lookup_states(forge, states)) do
    local result =
      vim.system(forge:pr_for_branch_cmd(branch, scope, list_state), { text = true }):wait()
    if result.code ~= 0 then
      return nil,
        system_mod.cmd_error(result, ('failed to fetch %s'):format(forge.labels.pr or 'PRs'))
    end
    for _, line in ipairs(vim.split(result.stdout or '', '\n', { plain = true, trimempty = true })) do
      local num = trim(line)
      if num and num ~= 'null' and not seen[num] then
        seen[num] = true
        nums[#nums + 1] = num
      end
    end
  end
  return nums
end

---@param forge forge.Forge
---@param branch string
---@param scope forge.Scope?
---@param states forge.PRLookupState[]
---@param callback fun(nums: string[]?, err: string?)
local function list_pr_numbers_async(forge, branch, scope, states, callback)
  local nums = {}
  local seen = {}
  local list_states = branch_lookup_states(forge, states)
  local index = 1
  local function step()
    local list_state = list_states[index]
    if not list_state then
      schedule_callback(callback, nums)
      return
    end
    vim.system(forge:pr_for_branch_cmd(branch, scope, list_state), { text = true }, function(result)
      if result.code ~= 0 then
        schedule_callback(
          callback,
          nil,
          system_mod.cmd_error(result, ('failed to fetch %s'):format(forge.labels.pr or 'PRs'))
        )
        return
      end
      for _, line in
        ipairs(vim.split(result.stdout or '', '\n', { plain = true, trimempty = true }))
      do
        local num = trim(line)
        if num and num ~= 'null' and not seen[num] then
          seen[num] = true
          nums[#nums + 1] = num
        end
      end
      index = index + 1
      step()
    end)
  end
  step()
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
    branch = target_mod.current_branch(parse_opts)
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
---@param states forge.PRLookupState[]
---@return forge.PRRef[]?, string?
local function matching_prs(forge, head, scope, states)
  local nums, list_err = list_pr_numbers(forge, head.branch, scope, states)
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
    if exact and lookup_states_include(states, pr_lookup_state(json)) then
      matches[#matches + 1] = {
        num = num,
        scope = scope,
      }
    end
  end
  return matches
end

---@param policy forge.BranchPRPolicy?
---@return forge.PRLookupPass[]
local function branch_pr_searches(policy)
  local searches = {}
  if type(policy) == 'table' and type(policy.searches) == 'table' then
    for _, pass in ipairs(policy.searches) do
      local states = {}
      local seen = {}
      if type(pass) == 'table' then
        for _, value in ipairs(pass) do
          local state = pr_lookup_state_name(value)
          if state and not seen[state] then
            seen[state] = true
            states[#states + 1] = state
          end
        end
      end
      if #states > 0 then
        searches[#searches + 1] = states
      end
    end
  end
  if #searches == 0 then
    return { { 'open' } }
  end
  return searches
end

---@param forge forge.Forge
---@param head forge.HeadRef
---@param scope forge.Scope
---@param states forge.PRLookupState[]
---@param callback fun(matches: forge.PRRef[]?, err: string?)
local function matching_prs_async(forge, head, scope, states, callback)
  list_pr_numbers_async(forge, head.branch, scope, states, function(nums, list_err)
    if not nums then
      callback(nil, list_err)
      return
    end
    local matches = {}
    local index = 1
    local function step()
      local num = nums[index]
      if not num then
        callback(matches)
        return
      end
      fetch_pr_json_async(forge, num, scope, function(json, fetch_err)
        if not json then
          callback(nil, fetch_err)
          return
        end
        local exact, match_err = head_matches(forge, head, pr_head(forge, json, scope))
        if match_err then
          callback(nil, match_err)
          return
        end
        if exact and lookup_states_include(states, pr_lookup_state(json)) then
          matches[#matches + 1] = {
            num = num,
            scope = scope,
          }
        end
        index = index + 1
        step()
      end)
    end
    step()
  end)
end

---@param repo forge.RepoLike?
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
---@param policy forge.BranchPRPolicy?
---@return forge.PRRef?, forge.CmdError?
function M.branch_pr(opts, policy)
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
  for _, states in ipairs(branch_pr_searches(policy)) do
    for _, scope in ipairs(repos) do
      local matches, match_err = matching_prs(forge, head, scope, states)
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
  end
  return nil
end

---@param opts forge.CurrentPROpts?
---@return forge.PRRef?, forge.CmdError?
function M.current_pr(opts)
  return M.branch_pr(opts, {
    searches = { { 'open' } },
  })
end

---@param opts forge.CurrentPROpts?
---@param callback fun(pr: forge.PRRef?, err: forge.CmdError?)
function M.current_pr_async(opts, callback)
  opts = opts or {}
  local finish = function(pr, err)
    schedule_callback(callback, pr, err)
  end
  local forge = current_forge(opts)
  if not forge then
    return finish(error_result('no forge detected', 'no_forge'))
  end
  local kind = forge_name(opts, forge)
  if not kind then
    return finish(error_result('no forge detected', 'no_forge'))
  end
  local parse_opts = target_mod.parse_opts(opts)
  local head, head_err = resolve_head(opts.head, opts, kind, parse_opts)
  if not head then
    return finish(
      error_result(
        head_err or 'invalid head',
        head_err == 'detached HEAD' and 'detached_head' or 'invalid_head'
      )
    )
  end
  local repos, repo_err, repo_code = candidate_scopes(opts, head, kind, parse_opts)
  if not repos then
    return finish(error_result(repo_err or 'invalid repo address', repo_code or 'invalid_repo'))
  end
  local searches = branch_pr_searches({
    searches = { { 'open' } },
  })
  local search_index = 1
  local repo_index = 1
  local function step()
    local states = searches[search_index]
    if not states then
      finish(nil, nil)
      return
    end
    local scope = repos[repo_index]
    if not scope then
      search_index = search_index + 1
      repo_index = 1
      step()
      return
    end
    matching_prs_async(forge, head, scope, states, function(matches, match_err)
      if not matches then
        finish(nil, {
          code = 'lookup_failed',
          message = match_err or 'current PR lookup failed',
        })
        return
      end
      if #matches == 1 then
        finish(matches[1], nil)
        return
      end
      if #matches > 1 then
        finish(nil, {
          code = 'ambiguous_pr',
          message = ('multiple %s match head %s; pass repo= or head='):format(
            forge.labels.pr_full or 'PRs',
            head_label(head)
          ),
        })
        return
      end
      repo_index = repo_index + 1
      step()
    end)
  end
  step()
end

return M
