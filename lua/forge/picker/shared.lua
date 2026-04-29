local layout = require('forge.layout')
local log = require('forge.logger')
local ops = require('forge.ops')
local picker_session = require('forge.picker.session')
local state_mod = require('forge.state')
local surface_policy = require('forge.surface_policy')

local M = {}

M.list_states = { 'open', 'closed', 'all' }

---@param text string
---@param kind? 'empty'|'error'
---@return forge.PickerEntry
local function placeholder_entry(text, kind)
  return {
    display = { { text, 'ForgeDim' } },
    value = nil,
    ordinal = text,
    placeholder = true,
    placeholder_kind = kind or 'empty',
  }
end

---@param failure forge.PickerSessionFailure?
---@param fallback string
---@return string
local function picker_failure_text(failure, fallback)
  return picker_session.failure_message(failure, fallback)
end

---@param failure forge.PickerSessionFailure?
---@param fallback string
---@return forge.PickerEntry
local function picker_failure_entry(failure, fallback)
  return placeholder_entry(picker_failure_text(failure, fallback), 'error')
end

---@param next_limit integer
---@param keep_open boolean?
---@return forge.PickerEntry
local function load_more_entry(next_limit, keep_open)
  local entry = {
    display = { { 'Load more...', 'ForgeDim' } },
    value = nil,
    ordinal = 'Load more',
    load_more = true,
    next_limit = next_limit,
  }
  if keep_open then
    entry.keep_open = true
  else
    entry.force_close = true
  end
  return entry
end

---@param entries forge.PickerEntry[]
---@param text string
---@return forge.PickerEntry[]
local function with_placeholder(entries, text)
  if #entries > 0 then
    return entries
  end
  return { placeholder_entry(text, 'empty') }
end

local function set_clipboard(text)
  local ok = pcall(vim.fn.setreg, '+', text)
  if not ok then
    pcall(vim.fn.setreg, '"', text)
  end
end

local function cached_rows(build)
  local cache = {}
  return function(width)
    width = width or layout.picker_width()
    local rows = cache[width]
    if rows == nil then
      rows = build(width)
      cache[width] = rows
    end
    return rows
  end
end

local function scoped_forge_ref(f, ref)
  if ref then
    return ref
  end
  local forge_mod = require('forge')
  if forge_mod.current_scope then
    return forge_mod.current_scope(f.name)
  end
  return nil
end

local function scoped_key(forge_mod, ref)
  if forge_mod.scope_key then
    return forge_mod.scope_key(ref)
  end
  return ''
end

local function scoped_id(id, suffix)
  if suffix ~= nil and suffix ~= '' then
    return id .. '|' .. suffix
  end
  return id
end

local function scoped_list_key(kind, state, suffix)
  if suffix ~= nil and suffix ~= '' then
    return state_mod.list_key(kind, state .. '|' .. suffix)
  end
  return state_mod.list_key(kind, state)
end

local function clear_state_caches(kind, suffix)
  for _, state in ipairs(M.list_states) do
    local key = scoped_list_key(kind, state, suffix)
    state_mod.clear_list(key)
    picker_session.invalidate(key)
  end
end

local function clear_list_cache(key)
  state_mod.clear_list(key)
  picker_session.invalidate(key)
end

local function refresh_picker(handle)
  return handle and type(handle.refresh) == 'function' and handle.refresh() == true
end

local function limit_settings(base_limit, requested_limit)
  local visible_limit = requested_limit or base_limit
  return {
    step = base_limit,
    visible = visible_limit,
    fetch = visible_limit + 1,
    use_cache = visible_limit == base_limit,
  }
end

---@param f forge.Forge
---@return string
local function ci_inline_label(f)
  return (f.labels and f.labels.ci_inline) or 'runs'
end

local function expanded_limit(limit, step)
  return limit + step
end

local function maybe_prefetch_list(kind, state, label, cmd, suffix)
  local key = scoped_list_key(kind, state, suffix)
  local started = picker_session.prefetch_json({
    key = key,
    cmd = cmd,
    skip_if = function()
      return state_mod.get_list(key) ~= nil
    end,
    on_success = function(data)
      state_mod.set_list(key, data)
    end,
  })
  if started then
    log.debug(('prefetching %s list (%s)...'):format(label, state))
  end
end

local function list_row(rows, field, id)
  if type(rows) ~= 'table' then
    return nil, nil
  end
  local target = tostring(id or '')
  for index, row in ipairs(rows) do
    if tostring(row[field] or '') == target then
      return index, row
    end
  end
  return nil, nil
end

local function remove_list_row(rows, field, id)
  local index, row = list_row(rows, field, id)
  if not index then
    return nil
  end
  table.remove(rows, index)
  return row
end

local function upsert_list_row(rows, field, id, row)
  local index = list_row(rows, field, id)
  if index then
    rows[index] = row
    return
  end
  rows[#rows + 1] = row
end

---@param pr forge.PRRefLike
---@return forge.PRRef
local function normalize_pr_ref(pr)
  if type(pr) == 'table' then
    return pr
  end
  return { num = pr }
end

---@param f forge.Forge
---@param pr forge.PRRef
---@return table<string, function>
local function pr_action_fns(f, pr)
  return {
    review = function()
      ops.pr_review(f, pr)
    end,
    ci = function(opts)
      ops.pr_ci(f, pr, opts)
    end,
    edit = function()
      ops.pr_edit(pr)
    end,
  }
end

local function issue_action_fns(f, issue)
  return {
    browse = function()
      ops.issue_browse(f, issue)
    end,
    edit = function()
      ops.issue_edit(issue)
    end,
  }
end

local function actionable_entry(entry)
  return entry ~= nil and not entry.load_more
end

local function picker_row_kind(entry)
  return surface_policy.row_kind(entry)
end

local function entity_row(entry)
  return picker_row_kind(entry) == 'entity'
end

local function load_more_row(entry)
  return picker_row_kind(entry) == 'load_more'
end

local function pr_toggle_entry(entry)
  return actionable_entry(entry) and surface_policy.pr_toggle_verb(entry) ~= nil
end

local function issue_toggle_entry(entry)
  return actionable_entry(entry) and surface_policy.issue_toggle_verb(entry) ~= nil
end

local function check_openable(entry)
  if not actionable_entry(entry) or entry.placeholder then
    return false
  end
  local c = entry.value
  if type(c) ~= 'table' then
    return false
  end
  if (c.bucket or ''):lower() == 'skipping' then
    return false
  end
  local run_id = c.run_id or (c.link or ''):match('/actions/runs/(%d+)')
  return run_id ~= nil
end

---@param f forge.Forge
---@param pr forge.PRRef
local function pr_toggle_draft_action(f, pr, opts)
  opts = opts or {}
  local is_draft = rawget(pr, 'is_draft')
  if is_draft == nil then
    local pr_state = state_mod.pr_state(f, pr.num, pr.scope)
    is_draft = pr_state.is_draft == true
  end
  ops.pr_toggle_draft(f, pr, is_draft, opts)
end

M.placeholder_entry = placeholder_entry
M.picker_failure_text = picker_failure_text
M.picker_failure_entry = picker_failure_entry
M.load_more_entry = load_more_entry
M.with_placeholder = with_placeholder
M.set_clipboard = set_clipboard
M.cached_rows = cached_rows
M.scoped_forge_ref = scoped_forge_ref
M.scoped_key = scoped_key
M.scoped_id = scoped_id
M.scoped_list_key = scoped_list_key
M.clear_state_caches = clear_state_caches
M.clear_list_cache = clear_list_cache
M.refresh_picker = refresh_picker
M.limit_settings = limit_settings
M.ci_inline_label = ci_inline_label
M.expanded_limit = expanded_limit
M.maybe_prefetch_list = maybe_prefetch_list
M.list_row = list_row
M.remove_list_row = remove_list_row
M.upsert_list_row = upsert_list_row
M.normalize_pr_ref = normalize_pr_ref
M.pr_action_fns = pr_action_fns
M.issue_action_fns = issue_action_fns
M.actionable_entry = actionable_entry
M.picker_row_kind = picker_row_kind
M.entity_row = entity_row
M.load_more_row = load_more_row
M.pr_toggle_entry = pr_toggle_entry
M.issue_toggle_entry = issue_toggle_entry
M.check_openable = check_openable
M.pr_toggle_draft_action = pr_toggle_draft_action

return M
