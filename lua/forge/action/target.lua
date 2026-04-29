local M = {}

local detect_mod = require('forge.detect')
local log = require('forge.logger')
local resolve_mod = require('forge.resolve')

---@return forge.Forge?
local function detect_or_warn()
  local forge = detect_mod.detect()
  if not forge then
    log.warn('no forge detected')
    return nil
  end
  return forge
end

---@param opts forge.CurrentPROpts?
---@param forge forge.Forge
---@return forge.CurrentPROpts
local function implicit_ref_opts(opts, forge)
  return vim.tbl_extend('force', { forge = forge }, opts or {})
end

---@param opts forge.PRActionOpts?
---@return string?, boolean
local function explicit_pr_num(opts)
  if type(opts) ~= 'table' then
    return nil, false
  end
  local num = opts.num
  if num == nil then
    return nil, false
  end
  ---@type string?
  local text = nil
  if type(num) == 'number' then
    text = tostring(num)
  elseif type(num) == 'string' then
    text = num
  end
  if text == nil then
    return nil, true
  end
  text = vim.trim(text)
  if text == '' then
    return nil, true
  end
  return text, true
end

---@param opts forge.PRActionOpts?
---@param forge forge.Forge?
---@return forge.PRRef?
local function resolve_explicit_pr(opts, forge)
  local num = explicit_pr_num(opts)
  if not num then
    return nil
  end
  ---@cast opts forge.PRActionOpts

  local scope = opts.scope
  if scope == nil and opts.repo ~= nil then
    forge = forge or detect_or_warn()
    if not forge then
      return nil
    end
    local repo_scope, scope_err = resolve_mod.repo(nil, implicit_ref_opts(opts, forge))
    if scope_err then
      log.warn(scope_err.message or 'invalid repo address')
      return nil
    end
    scope = repo_scope
  end

  return {
    num = num,
    scope = scope,
  }
end

---@param opts forge.ReviewOpts?
---@return { adapter: string? }
local function review_action_opts(opts)
  return {
    adapter = type(opts) == 'table' and opts.adapter or nil,
  }
end

---@param opts forge.CurrentPROpts?
---@return forge.Forge?, forge.PRRef?
local function resolve_action_pr(opts)
  local forge = detect_or_warn()
  if not forge then
    return nil
  end
  local pr, err = resolve_mod.current_pr(implicit_ref_opts(opts, forge))
  if err then
    log.warn(err.message or 'current PR lookup failed')
    return nil
  end
  if pr then
    return forge, pr
  end
  log.warn(('no open %s found for this branch'):format(forge.labels.pr_one or 'PR'))
  return nil
end

---@param opts forge.PRActionOpts?
---@param require_forge boolean?
---@return forge.Forge?, forge.PRRef?
function M.resolve_pr_action(opts, require_forge)
  local num, explicit = explicit_pr_num(opts)
  if explicit then
    local forge = nil
    if require_forge or (type(opts) == 'table' and opts.repo ~= nil) then
      forge = detect_or_warn()
      if not forge then
        return nil
      end
    end
    if not num then
      local f = forge or detect_mod.detect()
      local label = (f and f.labels and f.labels.pr_one) or 'PR'
      log.warn('missing ' .. label .. ' number')
      return nil
    end
    return forge, resolve_explicit_pr(opts, forge)
  end
  return resolve_action_pr(opts)
end

---@param opts forge.PRActionOpts?
---@return forge.Forge?, forge.PRRef?
function M.resolve_pr_ci(opts)
  local _, explicit = explicit_pr_num(opts)
  if explicit then
    return M.resolve_pr_action(opts, true)
  end
  local forge = detect_or_warn()
  if not forge then
    return nil
  end
  local pr, err = resolve_mod.branch_pr(implicit_ref_opts(opts, forge), {
    searches = {
      { 'open' },
      { 'closed', 'merged' },
    },
  })
  if err then
    log.warn(err.message or 'PR lookup failed')
    return nil
  end
  if pr then
    return forge, pr
  end
  log.warn(('no %s found for this branch'):format(forge.labels.pr_one or 'PR'))
  return nil
end

---@param opts forge.BranchCIOpts?
---@return forge.Forge?, forge.HeadRef?
function M.resolve_ci_head(opts)
  local forge = detect_or_warn()
  if not forge then
    return nil
  end

  opts = opts or {}
  local head_input = opts.head
  if
    head_input == nil and (opts.branch ~= nil or opts.head_branch ~= nil or opts.head_scope ~= nil)
  then
    head_input = {
      branch = opts.branch or opts.head_branch,
      scope = opts.head_scope,
    }
  end

  local head, head_err = resolve_mod.head(head_input, implicit_ref_opts(opts, forge))
  if not head then
    log.warn((head_err and head_err.message) or 'invalid head')
    return nil
  end

  if opts.repo ~= nil or opts.scope ~= nil then
    local scope, scope_err = resolve_mod.repo(nil, implicit_ref_opts(opts, forge))
    if scope_err then
      log.warn(scope_err.message or 'invalid repo address')
      return nil
    end
    head.scope = scope or head.scope
  end

  return forge, head
end

---@param opts forge.PRActionOpts?
function M.pr(opts)
  local forge, pr = M.resolve_pr_action(opts)
  if not pr then
    return
  end
  require('forge.action.ops').pr_edit(pr, forge)
end

---@param opts forge.ReviewOpts?
function M.review(opts)
  local forge, pr = M.resolve_pr_action(opts, true)
  if not forge or not pr then
    return
  end
  require('forge.action.ops').pr_review(forge, pr, review_action_opts(opts))
end

---@param opts forge.PRActionOpts?
function M.pr_ci(opts)
  local forge, pr = M.resolve_pr_ci(opts)
  if not forge or not pr then
    return
  end
  require('forge.action.ops').pr_ci(forge, pr)
end

---@param opts forge.BranchCIOpts?
function M.ci(opts)
  local forge, head = M.resolve_ci_head(opts)
  if not forge or not head then
    return
  end
  require('forge.action.ops').ci(forge, head)
end

return M
