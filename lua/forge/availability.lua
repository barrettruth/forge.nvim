local M = {}

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
  if value.is_draft ~= nil then
    return {
      review_decision = '',
      is_draft = value.is_draft == true,
    }
  end
  return require('forge').pr_state(f, value.num, value.scope)
end

local function pr_open(entry)
  return require('forge.picker').pr_toggle_verb(entry) == 'close'
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

function M.pr_can_merge(f, entry)
  if not pr_open(entry) then
    return false
  end
  local state = pr_state(f, entry)
  if state and state.is_draft then
    return false
  end
  local value = entry_value(entry)
  local info = require('forge').repo_info(f, value and value.scope or nil)
  return merge_permission(info)
    and type((info or {}).merge_methods) == 'table'
    and #info.merge_methods > 0
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
