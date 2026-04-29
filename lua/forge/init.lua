local M = {}

local action_mod = require('forge.action')
local action_target_mod = require('forge.action_target')
local config_mod = require('forge.config')
local context_mod = require('forge.context')
local detect_mod = require('forge.detect')
local format_mod = require('forge.format')
local issue_mod = require('forge.issue')
local pr_mod = require('forge.pr')
local repo_mod = require('forge.repo')
local review_mod = require('forge.review')
local routes_mod = require('forge.routes')
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

---@type fun(): string[]
M.review_adapter_names = review_mod.names

---@type fun(f: forge.Forge, scope?: forge.Scope): forge.RepoInfo
M.repo_info = repo_mod.repo_info

---@type fun(f: forge.Forge, num: string, scope?: forge.Scope): forge.PRState
M.pr_state = pr_mod.pr_state

---@type fun(num: string, state: forge.PRState, scope?: forge.Scope): forge.PRState
M.set_pr_state = pr_mod.set_pr_state

---@type fun(num?: string, scope?: forge.Scope)
M.clear_pr_state = pr_mod.clear_pr_state

---@type fun(kind: string, state: string): string
M.list_key = state_mod.list_key

---@type fun(key: string): table[]?
M.get_list = state_mod.get_list

---@type fun(key: string, data: table[])
M.set_list = state_mod.set_list

---@type fun(key?: string)
M.clear_list = state_mod.clear_list

---@type fun(kind: string)
M.clear_list_kind = state_mod.clear_list_kind

function M.clear_cache()
  detect_mod.clear_cache()
  state_mod.clear_cache()
end

---@type fun(): forge.Status?
M.status = state_mod.status

---@type fun(range?: { start_line: integer, end_line: integer }): string
M.file_loc = repo_mod.file_loc

---@type fun(scope?: forge.Scope): string
M.remote_web_url = repo_mod.remote_web_url

---@type fun(name: forge.ScopeKind, url: string): forge.Scope?
M.scope_from_url = repo_mod.scope_from_url

---@type fun(scope: forge.Scope?): string?
M.scope_repo_arg = repo_mod.scope_repo_arg

---@type fun(scope: forge.Scope?): string
M.scope_key = repo_mod.scope_key

---@type fun(name?: forge.ScopeKind): forge.Scope?
M.current_scope = repo_mod.current_scope

---@type fun(scope: forge.Scope?): string?
M.remote_name = repo_mod.remote_name

---@type fun(scope: forge.Scope?, branch: string): string?
M.remote_ref = repo_mod.remote_ref

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

---@type fun(opts?: forge.PRActionOpts)
M.pr = pr_mod.pr

---@type fun(opts?: forge.ReviewOpts)
M.review = pr_mod.review

---@type fun(opts?: forge.PRActionOpts)
M.pr_ci = pr_mod.pr_ci

---@type fun(opts?: forge.BranchCIOpts)
M.ci = action_target_mod.ci

---@type fun(opts?: forge.CreatePROpts)
M.create_pr = pr_mod.create_pr

---@type fun(opts?: forge.CreateIssueOpts)
M.create_issue = issue_mod.create_issue

---@type fun(num: string, ref?: forge.Scope)
M.edit_issue = issue_mod.edit_issue

---@type fun(): string[]
M.template_slugs = issue_mod.template_slugs

M._discover_templates = template_mod.discover
M._load_template = template_mod.load
M._normalize_body = template_mod.normalize_body

---@type fun(opts?: forge.PRActionOpts)
M.current_pr = pr_mod.current_pr
M.current_context = routes_mod.current_context
M.open = routes_mod.open

return M
