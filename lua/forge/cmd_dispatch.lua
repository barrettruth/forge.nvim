local M = {}

local log = require('forge.logger')
local ops = require('forge.ops')
local resolve_mod = require('forge.cmd_resolve')
local state_mod = require('forge.state')

---@param command forge.Command
local function dispatch_pr(command)
  if not resolve_mod.require_git_or_warn() then
    return
  end
  local f, forge_mod = resolve_mod.require_forge_or_warn()
  if not f or not forge_mod then
    return
  end
  local num = command.subjects[1]
  if command.name == 'create' then
    forge_mod.create_pr(resolve_mod.create_pr_opts(command, f.name))
    return
  end
  if command.name == 'open' then
    if num then
      ops.pr_edit({ num = num, scope = resolve_mod.resolve_repo_modifier(command, f.name) })
      return
    end
    local pr = resolve_mod.resolve_current_pr_or_warn(command, f)
    if not pr then
      return
    end
    ops.pr_edit(pr)
    return
  end
  if command.name == 'ci' then
    local pr = num and { num = num, scope = resolve_mod.resolve_repo_modifier(command, f.name) }
      or resolve_mod.resolve_branch_pr_or_warn(command, f, {
        searches = {
          { 'open' },
          { 'closed', 'merged' },
        },
      }, ('no %s found for this branch'):format((f.labels and f.labels.pr_one) or 'PR'))
    if not pr then
      return
    end
    ops.pr_ci(f, pr)
    return
  end
  if command.name == 'browse' then
    local scope = resolve_mod.resolve_repo_modifier(command, f.name)
    if num then
      ops.pr_browse(f, { num = num, scope = scope })
    else
      ops.list_browse(f, 'pr', { scope = scope })
    end
    return
  end
  if command.name == 'refresh' then
    state_mod.clear_list_kind('pr')
    log.info('refreshed ' .. ((f.labels and f.labels.pr) or 'pr') .. ' list')
    return
  end
  local function action_pr()
    if num then
      return { num = num, scope = resolve_mod.resolve_repo_modifier(command, f.name) }
    end
    return resolve_mod.resolve_current_pr_or_warn(command, f)
  end
  if command.name == 'edit' then
    ops.pr_edit({ num = num, scope = resolve_mod.resolve_repo_modifier(command, f.name) })
    return
  end
  if command.name == 'approve' then
    local pr = action_pr()
    if not pr then
      return
    end
    ops.pr_approve(f, pr)
    return
  end
  if command.name == 'merge' then
    local pr = action_pr()
    if not pr then
      return
    end
    ops.pr_merge(f, pr, command.modifiers.method)
    return
  end
  if command.name == 'draft' then
    local pr = action_pr()
    if not pr then
      return
    end
    ops.pr_toggle_draft(f, pr, false)
    return
  end
  if command.name == 'ready' then
    local pr = action_pr()
    if not pr then
      return
    end
    ops.pr_toggle_draft(f, pr, true)
    return
  end
  if command.name == 'close' then
    local pr = action_pr()
    if not pr then
      return
    end
    ops.pr_close(f, pr)
    return
  end
  if command.name == 'reopen' then
    local pr = num and { num = num, scope = resolve_mod.resolve_repo_modifier(command, f.name) }
      or resolve_mod.resolve_branch_pr_or_warn(command, f, {
        searches = {
          { 'closed' },
        },
      }, ('no reopenable %s found for this branch'):format(
        (f.labels and f.labels.pr_one) or 'PR'
      ))
    if not pr then
      return
    end
    ops.pr_reopen(f, pr)
    return
  end
  log.warn(('unsupported pr action: %s'):format(command.name))
end

---@param command forge.Command
local function dispatch_review(command)
  if not resolve_mod.require_git_or_warn() then
    return
  end
  local f = resolve_mod.require_forge_or_warn()
  if not f then
    return
  end
  local num = command.subjects[1]
  local opts = {
    adapter = command.modifiers.adapter ~= true and command.modifiers.adapter or nil,
  }
  if num then
    ops.pr_review(
      f,
      { num = num, scope = resolve_mod.resolve_repo_modifier(command, f.name) },
      opts
    )
    return
  end
  local pr = resolve_mod.resolve_current_pr_or_warn(command, f)
  if not pr then
    return
  end
  ops.pr_review(f, pr, opts)
end

---@param command forge.Command
local function dispatch_issue(command)
  if not resolve_mod.require_git_or_warn() then
    return
  end
  local f, forge_mod = resolve_mod.require_forge_or_warn()
  if not f or not forge_mod then
    return
  end
  local num = command.subjects[1]
  local scope = resolve_mod.resolve_repo_modifier(command, f.name)
  if command.name == 'create' then
    forge_mod.create_issue(resolve_mod.create_issue_opts(command, f.name))
    return
  end
  if command.name == 'browse' then
    if num then
      ops.issue_browse(f, { num = num, scope = scope })
    else
      ops.list_browse(f, 'issue', { scope = scope })
    end
    return
  end
  if command.name == 'edit' then
    ops.issue_edit({ num = num, scope = scope })
    return
  end
  if command.name == 'close' then
    ops.issue_close(f, { num = num, scope = scope })
    return
  end
  if command.name == 'reopen' then
    ops.issue_reopen(f, { num = num, scope = scope })
    return
  end
  if command.name == 'refresh' then
    state_mod.clear_list_kind('issue')
    log.info('refreshed issue list')
    return
  end
  log.warn(('unsupported issue action: %s'):format(command.name))
end

---@param command forge.Command
local function dispatch_ci(command)
  if not resolve_mod.require_git_or_warn() then
    return
  end
  if command.name == 'open' and command.subjects[1] == nil then
    require('forge').ci({
      repo = command.parsed_modifiers.repo,
      head = command.parsed_modifiers.head,
    })
    return
  end
  local f = resolve_mod.require_forge_or_warn()
  if not f then
    return
  end
  local scope = resolve_mod.resolve_repo_modifier(command, f.name)
  if command.name == 'open' then
    ops.ci_open(f, { id = command.subjects[1], scope = scope })
    return
  end
  if command.name == 'browse' then
    local id = command.subjects[1]
    if id then
      ops.ci_browse(f, { id = id, scope = scope })
    else
      ops.list_browse(f, 'ci', { scope = scope })
    end
    return
  end
  if command.name == 'refresh' then
    state_mod.clear_list_kind('ci')
    log.info('refreshed CI run list')
    return
  end
  log.warn(('unsupported ci action: %s'):format(command.name))
end

---@param command forge.Command
local function dispatch_release(command)
  if not resolve_mod.require_git_or_warn() then
    return
  end
  local f = resolve_mod.require_forge_or_warn()
  if not f then
    return
  end
  local tag = command.subjects[1]
  local scope = resolve_mod.resolve_repo_modifier(command, f.name)
  if command.name == 'browse' then
    if tag then
      ops.release_browse(f, { tag = tag, scope = scope })
    else
      ops.list_browse(f, 'release', { scope = scope })
    end
    return
  end
  if command.name == 'delete' then
    ops.release_delete(f, { tag = tag, scope = scope })
    return
  end
  if command.name == 'refresh' then
    state_mod.clear_list_kind('release')
    log.info('refreshed release list')
    return
  end
end

---@param command forge.Command
local function dispatch_browse(command)
  if not resolve_mod.require_git_or_warn() then
    return
  end
  local f, forge_mod = resolve_mod.require_forge_or_warn()
  if not f or not forge_mod then
    return
  end
  local scope = resolve_mod.resolve_scope_modifier(command, f.name)
  local subject = command.subjects[1]
  if subject then
    ops.browse_subject(f, { num = subject, scope = scope })
    return
  end
  local location = command.parsed_modifiers.target
  if location then
    local branch = location.rev and location.rev.rev or nil
    if not branch then
      local explicit_branch = command.parsed_modifiers.branch
      branch = explicit_branch and explicit_branch.branch or nil
    end
    if not branch then
      local ctx = forge_mod.current_context()
      branch = type(ctx) == 'table' and ctx.branch or nil
    end
    if ops.browse_location(f, location, scope, branch) then
      return
    end
    log.warn('detached HEAD')
    return
  end
  local commit = command.parsed_modifiers.commit
  if commit and commit.commit then
    forge_mod.open('browse.commit', { commit = commit.commit, scope = scope })
    return
  end
  local branch = command.parsed_modifiers.branch
  local file_loc = forge_mod.file_loc(command.range)
  if branch and branch.branch then
    if ops.browse_file(f, file_loc, branch.branch, scope) then
      return
    end
    forge_mod.open('browse.branch', { branch = branch.branch, scope = scope })
    return
  end
  local ctx = forge_mod.current_context()
  local ctx_branch = type(ctx) == 'table' and ctx.branch or nil
  if ops.browse_file(f, file_loc, ctx_branch, scope) then
    return
  end
  ops.browse_repo({ scope = scope })
end

local dispatchers = {
  pr = dispatch_pr,
  review = dispatch_review,
  issue = dispatch_issue,
  ci = dispatch_ci,
  release = dispatch_release,
  browse = dispatch_browse,
  clear = function()
    state_mod.clear_cache()
    log.info('cache cleared')
  end,
}

---@param command forge.Command
---@return boolean
function M.dispatch(command)
  local dispatcher = dispatchers[command.family]
  if not dispatcher then
    log.warn('unknown command: ' .. command.family)
    return false
  end
  dispatcher(command)
  return true
end

return M
