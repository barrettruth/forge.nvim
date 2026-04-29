local M = {}

local config_mod = require('forge.config')
local detect_mod = require('forge.detect')
local repo_mod = require('forge.repo')
local state_mod = require('forge.state')
local target_mod = require('forge.target')

local completion_limits = {
  pr = 100,
  issue = 100,
  ci = 30,
  release = 30,
}

---@return forge.TargetParseOpts
local function target_parse_opts()
  return target_mod.parse_opts()
end

---@param cmd string[]|string
---@return string[]
local function system_lines(cmd)
  if type(cmd) == 'table' then
    local result = vim.system(cmd, { text = true }):wait()
    if result.code ~= 0 then
      return {}
    end
    local output = vim.trim(result.stdout or '')
    return output == '' and {} or vim.split(output, '\n', { plain = true, trimempty = true })
  end
  local lines = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return {}
  end
  return lines
end

---@param items string[]
---@param seen table<string, boolean>
---@param value string?
local function add_completion_candidate(items, seen, value)
  if type(value) ~= 'string' or value == '' or seen[value] then
    return
  end
  seen[value] = true
  items[#items + 1] = value
end

---@param id string
---@param suffix string?
---@return string
local function scoped_id(id, suffix)
  if suffix ~= nil and suffix ~= '' then
    return id .. '|' .. suffix
  end
  return id
end

---@param cmd table?
---@return table[]?
local function json_list(cmd)
  if type(cmd) ~= 'table' then
    return nil
  end
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  local ok, data = pcall(vim.json.decode, result.stdout or '[]')
  if not ok or type(data) ~= 'table' then
    return nil
  end
  return data
end

---@param scope forge.Scope?
---@return string
local function completion_scope_key(scope)
  return repo_mod.scope_key(scope)
end

---@param kind string
---@return integer
local function completion_limit(kind)
  local cfg = config_mod.config()
  local display = type(cfg) == 'table' and cfg.display or nil
  local limits = type(display) == 'table' and display.limits or nil
  if kind == 'pr' then
    return type(limits) == 'table' and limits.pulls or completion_limits.pr
  end
  if kind == 'issue' then
    return type(limits) == 'table' and limits.issues or completion_limits.issue
  end
  if kind == 'ci' then
    return type(limits) == 'table' and limits.runs or completion_limits.ci
  end
  if kind == 'release' then
    return type(limits) == 'table' and limits.releases or completion_limits.release
  end
  return 50
end

---@param f forge.Forge
---@param state forge.CommandCompletionState
---@return forge.Scope?
local function completion_scope(f, state)
  local repo = state.modifiers.repo
  if type(repo) == 'string' and repo ~= '' then
    local resolved = target_mod.resolve_repo(repo, target_parse_opts())
    if resolved then
      return target_mod.repo_scope(resolved, f.name)
    end
  end
  return repo_mod.current_scope(f.name)
end

---@param kind string
---@param state string
---@param scope forge.Scope?
---@return string
local function completion_list_key(kind, state, scope)
  return state_mod.list_key(kind, scoped_id(state, completion_scope_key(scope)))
end

---@param kind string
---@param states string[]
---@param scope forge.Scope?
---@return table[]?
local function cached_completion_list(kind, states, scope)
  local items = {}
  local found = false
  for _, state in ipairs(states) do
    local cached = state_mod.get_list(completion_list_key(kind, state, scope))
    if type(cached) == 'table' then
      found = true
      for _, item in ipairs(cached) do
        items[#items + 1] = item
      end
    end
  end
  if found then
    return items
  end
  return nil
end

---@param f forge.Forge
---@param kind string
---@param state string
---@param scope forge.Scope?
---@return table[]
local function fetch_completion_list(f, kind, state, scope)
  local limit = completion_limit(kind)
  local cmd = nil
  if kind == 'pr' and type(f.list_pr_json_cmd) == 'function' then
    cmd = f:list_pr_json_cmd(state, limit, scope)
  elseif kind == 'issue' and type(f.list_issue_json_cmd) == 'function' then
    cmd = f:list_issue_json_cmd(state, limit, scope)
  elseif kind == 'ci' and type(f.list_runs_json_cmd) == 'function' then
    cmd = f:list_runs_json_cmd(state == 'all' and nil or state, scope, limit)
  elseif kind == 'release' and type(f.list_releases_json_cmd) == 'function' then
    cmd = f:list_releases_json_cmd(scope, limit)
  end
  local data = json_list(cmd)
  if type(data) ~= 'table' then
    return {}
  end
  if kind == 'ci' and type(f.normalize_run) == 'function' then
    local normalized = {}
    for _, item in ipairs(data) do
      normalized[#normalized + 1] = f:normalize_run(item)
    end
    data = normalized
  end
  state_mod.set_list(completion_list_key(kind, state, scope), data)
  return data
end

---@param candidates string[]
---@param arglead string
---@return string[]
function M.filter(candidates, arglead)
  return vim.tbl_filter(function(s)
    return s:find(arglead, 1, true) == 1
  end, candidates)
end

---@param prefix string
---@return string[]
function M.repo_values(prefix)
  local parse_opts = target_parse_opts()
  local items = {}
  local seen = {}
  local alias_names = {}
  for name in pairs(parse_opts.aliases or {}) do
    alias_names[#alias_names + 1] = name
  end
  table.sort(alias_names)
  for _, name in ipairs(alias_names) do
    add_completion_candidate(items, seen, name)
  end
  for _, remote in ipairs(system_lines({ 'git', 'remote' })) do
    add_completion_candidate(items, seen, remote)
    local resolved = target_mod.resolve_repo(remote, parse_opts)
    if resolved then
      add_completion_candidate(items, seen, resolved.slug)
      if resolved.host and resolved.slug then
        add_completion_candidate(items, seen, resolved.host .. '/' .. resolved.slug)
      end
    end
  end
  for _, repo in ipairs({
    target_mod.current_repo(parse_opts),
    target_mod.push_repo(parse_opts),
    target_mod.collaboration_repo(parse_opts),
  }) do
    if repo then
      add_completion_candidate(items, seen, repo.slug)
      if repo.host and repo.slug then
        add_completion_candidate(items, seen, repo.host .. '/' .. repo.slug)
      end
    end
  end
  return M.filter(items, prefix)
end

---@param prefix string
---@return string[]
function M.ref_values(prefix)
  local items = {}
  local seen = {}
  for _, ref in
    ipairs(system_lines('git for-each-ref --format=%(refname:short) refs/heads refs/tags'))
  do
    add_completion_candidate(items, seen, ref)
  end
  for _, sha in
    ipairs(system_lines({ 'git', 'rev-list', '--max-count=20', '--abbrev-commit', 'HEAD' }))
  do
    add_completion_candidate(items, seen, sha)
  end
  return M.filter(items, prefix)
end

---@param prefix string
---@return string[]
function M.sha_values(prefix)
  return M.filter(
    system_lines({ 'git', 'rev-list', '--max-count=20', '--abbrev-commit', 'HEAD' }),
    prefix
  )
end

---@param prefix string
---@return string[]
function M.rev_values(prefix)
  local items = {}
  local seen = {}
  local at = prefix:find('@', 1, true)
  if at then
    local repo = prefix:sub(1, at - 1)
    local rev_prefix = prefix:sub(at + 1)
    local base = repo ~= '' and (repo .. '@') or '@'
    for _, ref in ipairs(M.ref_values(rev_prefix)) do
      add_completion_candidate(items, seen, base .. ref)
    end
    return items
  end
  for _, repo in ipairs(M.repo_values(prefix)) do
    add_completion_candidate(items, seen, repo .. '@')
  end
  for _, ref in ipairs(M.ref_values('')) do
    add_completion_candidate(items, seen, '@' .. ref)
  end
  return M.filter(items, prefix)
end

---@param prefix string
---@return string[]
function M.target_values(prefix)
  if prefix:find(':', 1, true) then
    return {}
  end
  local items = {}
  local seen = {}
  local at = prefix:find('@', 1, true)
  if at then
    for _, value in ipairs(M.rev_values(prefix)) do
      add_completion_candidate(items, seen, value .. ':')
    end
    return items
  end
  for _, repo in ipairs(M.repo_values(prefix)) do
    add_completion_candidate(items, seen, repo .. '@')
  end
  for _, ref in ipairs(M.ref_values('')) do
    add_completion_candidate(items, seen, '@' .. ref .. ':')
  end
  return M.filter(items, prefix)
end

---@param state forge.CommandCompletionState
---@return forge.Forge?, forge.Scope?
function M.forge(state)
  local f = detect_mod.detect()
  if not f then
    return nil, nil
  end
  return f, completion_scope(f, state)
end

---@param f forge.Forge
---@param kind string
---@param states string[]
---@param fetch_state string?
---@param scope forge.Scope?
---@return table[]
function M.list(f, kind, states, fetch_state, scope)
  return cached_completion_list(kind, states, scope)
    or fetch_completion_list(f, kind, fetch_state or states[1], scope)
end

---@param value string?
---@param forge_name forge.ScopeKind
---@return forge.Scope?
function M.repo_scope(value, forge_name)
  if type(value) ~= 'string' or value == '' then
    return nil
  end
  return target_mod.resolve_scope(value, forge_name, target_parse_opts())
end

---@param value forge.RepoLike?
---@return forge.Scope?
function M.repo_like_scope(value)
  if type(value) ~= 'table' or value.kind == 'repo' then
    return nil
  end
  return value
end

---@param value string?
---@return forge.RevTarget?
function M.head(value)
  if type(value) ~= 'string' or value == '' then
    return nil
  end
  return target_mod.parse_rev(value, target_parse_opts())
end

return M
