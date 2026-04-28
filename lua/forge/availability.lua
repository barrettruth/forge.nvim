local M = {}
local surface_policy = require('forge.surface_policy')

local function entry_value(entry)
  if type(entry) ~= 'table' or type(entry.value) ~= 'table' then
    return nil
  end
  if entry.placeholder or entry.load_more then
    return nil
  end
  return entry.value
end

local function pr_state(f, entry)
  local value = entry_value(entry)
  if not value then
    return nil
  end
  if value.review_decision ~= nil or value.is_draft ~= nil or value.mergeable ~= nil then
    return {
      state = value.state or '',
      mergeable = value.mergeable or '',
      review_decision = value.review_decision or '',
      is_draft = value.is_draft == true,
    }
  end
  return require('forge').pr_state(f, value.num, value.scope)
end

local function pr_open(entry)
  return surface_policy.pr_toggle_verb(entry) == 'close'
end

local function merge_permission(info)
  local permission = ((info or {}).permission or ''):upper()
  return permission == 'WRITE' or permission == 'ADMIN' or permission == 'MAINTAIN'
end

function M.pr_can_approve(f, entry)
  if not pr_open(entry) then
    return false
  end
  local state = pr_state(f, entry)
  return state == nil or (state.review_decision or ''):upper() ~= 'APPROVED'
end

function M.pr_merge_methods(f, entry)
  if not pr_open(entry) then
    return {}
  end
  local state = pr_state(f, entry)
  if state and state.is_draft then
    return {}
  end
  local value = entry_value(entry)
  local info = require('forge').repo_info(f, value and value.scope or nil)
  if not merge_permission(info) or type((info or {}).merge_methods) ~= 'table' then
    return {}
  end
  return info.merge_methods
end

function M.pr_can_merge(f, entry)
  return #M.pr_merge_methods(f, entry) > 0
end

function M.pr_can_toggle_draft(f, entry)
  return f.capabilities.draft and pr_open(entry)
end

function M.pr_can_mark_draft(f, entry)
  if not M.pr_can_toggle_draft(f, entry) then
    return false
  end
  local state = pr_state(f, entry)
  return not (state and state.is_draft)
end

function M.pr_can_mark_ready(f, entry)
  if not M.pr_can_toggle_draft(f, entry) then
    return false
  end
  local state = pr_state(f, entry)
  return state ~= nil and state.is_draft == true
end

function M.pr_draft_label(f, entry)
  if entry == nil then
    return 'draft/ready'
  end
  local state = pr_state(f, entry)
  if state and state.is_draft then
    return 'ready'
  end
  return 'draft'
end

return M
