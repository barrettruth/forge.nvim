local M = {}

local action_mod = require('forge.action')
local config_mod = require('forge.config')
local context_mod = require('forge.context')
local detect_mod = require('forge.detect')
local format_mod = require('forge.format')
local repo_mod = require('forge.repo')
local resolve_mod = require('forge.resolve')
local review_mod = require('forge.review')
local state_mod = require('forge.state')
local template_mod = require('forge.template')

M.register = detect_mod.register
M.register_source = M.register
M.register_context_provider = context_mod.register
M.register_action = action_mod.register
M.register_review_adapter = review_mod.register
M.run_action = action_mod.run
M.registered_sources = detect_mod.registered_sources
M.detect = detect_mod.detect

function M.review_adapter_names()
  return review_mod.names()
end

---@param f forge.Forge
---@param scope? forge.Scope
---@return forge.RepoInfo
function M.repo_info(f, scope)
  return state_mod.repo_info(f, scope)
end

---@param f forge.Forge
---@param num string
---@param scope? forge.Scope
---@return forge.PRState
function M.pr_state(f, num, scope)
  return state_mod.pr_state(f, num, scope)
end

---@param num string
---@param state forge.PRState
---@param scope? forge.Scope
---@return forge.PRState
function M.set_pr_state(num, state, scope)
  return state_mod.set_pr_state(num, state, scope)
end

---@param num? string
---@param scope? forge.Scope
function M.clear_pr_state(num, scope)
  state_mod.clear_pr_state(num, scope)
end

---@param kind string
---@param state string
---@return string
function M.list_key(kind, state)
  return state_mod.list_key(kind, state)
end

---@param key string
---@return table[]?
function M.get_list(key)
  return state_mod.get_list(key)
end

---@param key string
---@param data table[]
function M.set_list(key, data)
  state_mod.set_list(key, data)
end

---@param key string?
function M.clear_list(key)
  state_mod.clear_list(key)
end

---@param kind string
function M.clear_list_kind(kind)
  state_mod.clear_list_kind(kind)
end

function M.clear_cache()
  detect_mod.clear_cache()
  state_mod.clear_cache()
end

---@return forge.Status?
function M.status()
  return state_mod.status()
end

---@param range? { start_line: integer, end_line: integer }
---@return string
function M.file_loc(range)
  return repo_mod.file_loc(range)
end

---@param scope? forge.Scope
---@return string
function M.remote_web_url(scope)
  return repo_mod.remote_web_url(scope)
end

---@param name forge.ScopeKind
---@param url string
---@return forge.Scope?
function M.scope_from_url(name, url)
  return repo_mod.scope_from_url(name, url)
end

---@param scope forge.Scope?
---@return string?
function M.scope_repo_arg(scope)
  return repo_mod.scope_repo_arg(scope)
end

---@param scope forge.Scope?
---@return string
function M.scope_key(scope)
  return repo_mod.scope_key(scope)
end

---@param name? forge.ScopeKind
---@return forge.Scope?
function M.current_scope(name)
  return repo_mod.current_scope(name)
end

---@param scope forge.Scope?
---@return string?
function M.remote_name(scope)
  return repo_mod.remote_name(scope)
end

---@param scope forge.Scope?
---@param branch string
---@return string?
function M.remote_ref(scope, branch)
  return repo_mod.remote_ref(scope, branch)
end

M.config = config_mod.config

M.format_pr = format_mod.format_pr
M.format_prs = format_mod.format_prs
M.format_issue = format_mod.format_issue
M.format_issues = format_mod.format_issues
M.format_check = format_mod.format_check
M.format_checks = format_mod.format_checks
M.format_run = format_mod.format_run
M.format_runs = format_mod.format_runs
M.format_release = format_mod.format_release
M.format_releases = format_mod.format_releases
M.filter_checks = format_mod.filter_checks
M.filter_runs = format_mod.filter_runs

---@param opts forge.PRActionOpts?
function M.pr(opts)
  require('forge.action_target').pr(opts)
end

---@param opts forge.ReviewOpts?
function M.review(opts)
  require('forge.action_target').review(opts)
end

---@param opts forge.PRActionOpts?
function M.pr_ci(opts)
  require('forge.action_target').pr_ci(opts)
end

---@param opts forge.BranchCIOpts?
function M.ci(opts)
  require('forge.action_target').ci(opts)
end

---@param opts forge.CreatePROpts?
function M.create_pr(opts)
  require('forge.creation').create_pr(opts)
end

---@param num string
---@param ref? forge.Scope
function M.edit_issue(num, ref)
  require('forge.ops').issue_edit({
    num = num,
    scope = ref,
  })
end

---@param opts forge.CreateIssueOpts?
function M.create_issue(opts)
  require('forge.creation').create_issue(opts)
end

---@return string[]
function M.template_slugs()
  return require('forge.creation').template_slugs()
end

M._discover_templates = template_mod.discover
M._load_template = template_mod.load
M._normalize_body = template_mod.normalize_body
M.current_pr = resolve_mod.current_pr

local routes_mod = require('forge.routes')
M.current_context = routes_mod.current_context
M.open = routes_mod.open

return M
