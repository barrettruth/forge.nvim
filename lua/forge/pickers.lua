local M = {}

local ops = require('forge.action.ops')
local picker_shared = require('forge.picker.shared')
local routes_mod = require('forge.routes')

local normalize_pr_ref = picker_shared.normalize_pr_ref
local pr_action_fns = picker_shared.pr_action_fns

---@param f forge.Forge
---@param num string
---@param filter string?
---@param cached_checks table[]?
---@param opts? forge.PickerLimitOpts
function M.checks(f, num, filter, cached_checks, opts)
  require('forge.picker.checks').pick(f, num, filter, cached_checks, opts)
end

---@param f forge.Forge
---@param branch string?
---@param filter string?
---@param opts? forge.PickerLimitOpts
function M.ci(f, branch, filter, opts)
  require('forge.picker.ci').pick(f, branch, filter, opts)
end

---@param state 'all'|'open'|'closed'
---@param f forge.Forge
---@param opts? forge.PickerLimitOpts
function M.pr(state, f, opts)
  require('forge.picker.pr').pick(state, f, opts)
end

---@param state 'all'|'open'|'closed'
---@param f forge.Forge
---@param opts? forge.PickerLimitOpts
function M.issue(state, f, opts)
  require('forge.picker.issue').pick(state, f, opts)
end

---@param state 'all'|'draft'|'prerelease'
---@param f forge.Forge
---@param opts? forge.PickerLimitOpts
function M.release(state, f, opts)
  require('forge.picker.release').pick(state, f, opts)
end

---@param f forge.Forge
---@param num string
---@param ref? forge.Scope
function M.issue_close(f, num, ref)
  ops.issue_close(f, { num = num, scope = ref })
end

---@param f forge.Forge
---@param num string
---@param ref? forge.Scope
function M.issue_reopen(f, num, ref)
  ops.issue_reopen(f, { num = num, scope = ref })
end

---@param f forge.Forge
---@param num string
---@param ref? forge.Scope
function M.pr_close(f, num, ref)
  ops.pr_close(f, { num = num, scope = ref })
end

---@param f forge.Forge
---@param num string
---@param ref? forge.Scope
function M.pr_reopen(f, num, ref)
  ops.pr_reopen(f, { num = num, scope = ref })
end

---@param f forge.Forge
---@param pr forge.PRRefLike
---@return table<string, function>
function M.pr_actions(f, pr)
  return pr_action_fns(f, normalize_pr_ref(pr))
end

function M.git()
  routes_mod.open()
end

return M
