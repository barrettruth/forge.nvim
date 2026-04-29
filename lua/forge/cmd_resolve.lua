local M = {}

local log = require('forge.logger')
local target_mod = require('forge.target')

---@return forge.TargetParseOpts
local function target_parse_opts()
  return target_mod.parse_opts()
end

---@param value forge.TargetValue|forge.HeadInput|forge.Scope|nil
---@return forge.RepoLike?
local function repo_target(value)
  return target_mod.repo_target(value)
end

---@return boolean
function M.require_git_or_warn()
  vim.fn.system('git rev-parse --show-toplevel')
  if vim.v.shell_error ~= 0 then
    log.warn('not a git repository')
    return false
  end
  return true
end

---@return forge.Forge?, table?
function M.require_forge_or_warn()
  local forge_mod = require('forge')
  local f = forge_mod.detect()
  if not f then
    log.warn('no forge detected')
    return nil, forge_mod
  end
  return f, forge_mod
end

---@param command forge.Command
---@param forge_name forge.ScopeKind
---@return forge.Scope?
function M.resolve_scope_modifier(command, forge_name)
  local repo = repo_target(command.parsed_modifiers.target)
    or repo_target(command.parsed_modifiers.base)
    or repo_target(command.parsed_modifiers.head)
    or repo_target(command.parsed_modifiers.repo)
    or repo_target(command.default_targets.target)
    or repo_target(command.default_targets.rev)
    or repo_target(command.default_targets.base)
    or repo_target(command.default_targets.head)
    or repo_target(command.default_targets.repo)
  return target_mod.resolve_scope(repo, forge_name, target_parse_opts())
end

---@param command forge.Command
---@param forge_name forge.ScopeKind
---@return forge.Scope?
function M.resolve_repo_modifier(command, forge_name)
  local repo = repo_target(command.parsed_modifiers.repo)
    or repo_target(command.default_targets.repo)
  return target_mod.resolve_scope(repo, forge_name, target_parse_opts())
end

---@param command forge.Command
---@param f forge.Forge
---@return forge.CurrentPROpts
function M.current_pr_resolution_opts(command, f)
  local opts = {
    forge = f,
  }
  if command.parsed_modifiers.repo ~= nil then
    opts.repo = command.parsed_modifiers.repo
  end
  if command.parsed_modifiers.head ~= nil then
    opts.head = command.parsed_modifiers.head
  end
  return opts
end

---@param command forge.Command
---@param f forge.Forge
---@return forge.PRRef?
function M.resolve_current_pr_or_warn(command, f)
  local pr, err = require('forge').current_pr(M.current_pr_resolution_opts(command, f))
  if err then
    log.warn(err.message)
    return nil
  end
  if pr then
    return pr
  end
  log.warn(('no open %s found for this branch'):format((f.labels and f.labels.pr_one) or 'PR'))
  return nil
end

---@param command forge.Command
---@param f forge.Forge
---@param policy table
---@param no_match string
---@return forge.PRRef?
function M.resolve_branch_pr_or_warn(command, f, policy, no_match)
  local pr, err =
    require('forge.resolve').branch_pr(M.current_pr_resolution_opts(command, f), policy)
  if err then
    log.warn(err.message)
    return nil
  end
  if pr then
    return pr
  end
  log.warn(no_match)
  return nil
end

---@param command forge.Command
---@param forge_name forge.ScopeKind
---@return forge.CreatePROpts
function M.create_pr_opts(command, forge_name)
  local parse_opts = target_parse_opts()
  local head = command.parsed_modifiers.head or command.default_targets.head
  local base = command.parsed_modifiers.base or command.default_targets.base
  local scope = M.resolve_repo_modifier(command, forge_name)
  return {
    draft = command.modifiers.draft == true,
    instant = command.modifiers.fill == true,
    web = command.modifiers.web == true,
    scope = scope,
    head_branch = head and head.rev or nil,
    head_scope = target_mod.resolve_scope(head, forge_name, parse_opts),
    base_branch = base and base.rev or nil,
    base_scope = target_mod.resolve_scope(base, forge_name, parse_opts) or scope,
  }
end

---@param command forge.Command
---@param forge_name forge.ScopeKind
---@return forge.CreateIssueOpts
function M.create_issue_opts(command, forge_name)
  local template = command.modifiers.template
  return {
    web = command.modifiers.web == true,
    blank = command.modifiers.blank == true,
    template = template ~= true and template or nil,
    scope = M.resolve_repo_modifier(command, forge_name),
  }
end

return M
