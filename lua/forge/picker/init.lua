local M = {}

---@alias forge.Segment {[1]: string, [2]: string?}

---@class forge.PickerEntry
---@field display forge.Segment[]
---@field value any
---@field ordinal string?
---@field placeholder boolean?
---@field keep_open? boolean
---@field force_close boolean?

---@alias forge.PickerActionLabel string|fun(entry: forge.PickerEntry?): string?
---@alias forge.PickerActionAvailability boolean|fun(entry: forge.PickerEntry?): boolean?

---@class forge.PickerActionDef
---@field name string
---@field label forge.PickerActionLabel?
---@field available forge.PickerActionAvailability?
---@field close boolean?
---@field reload boolean?
---@field fn fun(entry: forge.PickerEntry?)

---@class forge.PickerOpts
---@field prompt string?
---@field entries forge.PickerEntry[]
---@field actions forge.PickerActionDef[]
---@field picker_name string
---@field back fun()?
---@field stream? fun(emit: fun(entry: forge.PickerEntry?))

local root_search_terms = {
  ['prs.all'] = { 'prs', 'pull', 'requests', 'reviews' },
  ['prs.open'] = { 'prs', 'pull', 'requests', 'reviews' },
  ['prs.closed'] = { 'prs', 'pull', 'requests', 'reviews' },
  ['issues.all'] = { 'issues', 'bugs', 'tickets' },
  ['issues.open'] = { 'issues', 'bugs', 'tickets' },
  ['issues.closed'] = { 'issues', 'bugs', 'tickets' },
  ['ci.all'] = { 'ci', 'checks', 'runs', 'actions' },
  ['ci.current_branch'] = { 'ci', 'checks', 'runs', 'actions' },
  ['browse.contextual'] = { 'browse', 'web' },
  ['browse.branch'] = { 'browse', 'web' },
  ['browse.commit'] = { 'browse', 'web' },
  ['releases.all'] = { 'releases', 'tags' },
  ['releases.draft'] = { 'releases', 'tags' },
  ['releases.prerelease'] = { 'releases', 'tags' },
}

local function flatten_display(entry)
  local parts = {}
  for _, seg in ipairs(entry.display or {}) do
    parts[#parts + 1] = seg[1]
  end
  return table.concat(parts)
end

local function join_search_terms(parts)
  local items = {}
  for _, part in ipairs(parts) do
    if type(part) == 'string' then
      local text = vim.trim(part)
      if text ~= '' then
        items[#items + 1] = text
      end
    end
  end
  return table.concat(items, ' ')
end

local function menu_search_key(entry)
  local value = entry.value
  if type(value) == 'table' then
    if value.path then
      return join_search_terms({ value.path, value.old_path or '' })
    end
    if value.name and value.display and value.dir then
      local slug = value.name:gsub('%.ya?ml$', ''):gsub('%.md$', '')
      return join_search_terms({ value.display, slug })
    end
  elseif type(value) == 'string' then
    local root_terms = root_search_terms[value]
    if root_terms then
      local display = flatten_display(entry)
      return join_search_terms(vim.list_extend({ display }, vim.deepcopy(root_terms)))
    end
    return value
  end
  return M.ordinal(entry)
end

M.search_keys = {
  _menu = menu_search_key,
  pr = function(entry)
    return M.ordinal(entry)
  end,
  issue = function(entry)
    return M.ordinal(entry)
  end,
  ci = function(entry)
    local value = entry.value
    if type(value) == 'table' then
      return join_search_terms({ value.name or '', value.branch or '' })
    end
    return M.ordinal(entry)
  end,
  release = function(entry)
    local value = entry.value
    if type(value) == 'table' then
      return join_search_terms({
        value.tag or '',
        type(value.rel) == 'table' and value.rel.title or '',
      })
    end
    return M.ordinal(entry)
  end,
}

---@param entry forge.PickerEntry
---@return string
function M.ordinal(entry)
  if entry.ordinal then
    return entry.ordinal
  end
  return flatten_display(entry)
end

---@param picker_name string
---@param entry forge.PickerEntry
---@return string
function M.search_key(picker_name, entry)
  local builder = M.search_keys[picker_name]
  if builder then
    return builder(entry)
  end
  return M.ordinal(entry)
end

---@param entry forge.PickerEntry?
---@return forge.PickerEntry?
function M.selected(entry)
  if entry and entry.placeholder then
    return nil
  end
  return entry
end

---@param def forge.PickerActionDef
---@param entry forge.PickerEntry?
---@return boolean
function M.closes(def, entry)
  if entry and entry.keep_open then
    return false
  end
  if entry and entry.force_close then
    return true
  end
  return rawget(def, 'close') ~= false
end

---@param def forge.PickerActionDef
---@param entry forge.PickerEntry?
---@return boolean
function M.available(def, entry)
  local available = rawget(def, 'available')
  if type(available) == 'function' then
    local ok, result = pcall(available, entry)
    return ok and result ~= false
  end
  if available ~= nil then
    return available ~= false
  end
  return true
end

---@param def forge.PickerActionDef
---@param entry forge.PickerEntry?
---@return string?
function M.resolve_label(def, entry)
  if not M.available(def, entry) then
    return nil
  end
  local label = rawget(def, 'label')
  if type(label) == 'function' then
    local ok, result = pcall(label, entry)
    if ok and type(result) == 'string' then
      return result
    end
    return nil
  end
  if type(label) == 'string' then
    return label
  end
  return nil
end

---@param def forge.PickerActionDef
---@return boolean
function M.has_dynamic_label(def)
  return type(rawget(def, 'label')) == 'function' or type(rawget(def, 'available')) == 'function'
end

---@param entry forge.PickerEntry?
---@return table?
local function entry_value(entry)
  if not entry or rawget(entry, 'placeholder') or rawget(entry, 'load_more') then
    return nil
  end
  if type(entry.value) ~= 'table' then
    return nil
  end
  return entry.value
end

---@alias forge.IssueToggleVerb 'close'|'reopen'

---Verb that the issue toggle action will execute on `entry`, or `nil` when no
---valid transition exists (missing/unknown state, placeholder, or load_more
---row).
---@param entry forge.PickerEntry?
---@return forge.IssueToggleVerb?
function M.issue_toggle_verb(entry)
  local value = entry_value(entry)
  if not value then
    return nil
  end
  local state = (value.state or ''):lower()
  if state == 'open' or state == 'opened' then
    return 'close'
  end
  if state == 'closed' then
    return 'reopen'
  end
  return nil
end

---@alias forge.PRToggleVerb 'close'|'reopen'

---Verb that the PR toggle action will execute on `entry`, or `nil` when no
---valid transition exists. Merged PRs return `nil` because merged is a
---terminal state (`gh pr reopen` and its GitLab/Codeberg analogues all
---refuse a merged PR).
---@param entry forge.PickerEntry?
---@return forge.PRToggleVerb?
function M.pr_toggle_verb(entry)
  local value = entry_value(entry)
  if not value then
    return nil
  end
  local state = (value.state or ''):lower()
  if state == 'open' or state == 'opened' then
    return 'close'
  end
  if state == 'closed' then
    return 'reopen'
  end
  return nil
end

---@alias forge.CIToggleVerb 'cancel'|'rerun'

---Verb that the CI toggle action will execute on `entry`, or `nil` when no
---valid transition exists. `skipped` runs return `nil` because neither
---cancel nor rerun makes sense for a workflow that never started.
---@param entry forge.PickerEntry?
---@return forge.CIToggleVerb?
function M.ci_toggle_verb(entry)
  local value = entry_value(entry)
  if not value then
    return nil
  end
  local status = (value.status or ''):lower()
  if
    status == 'in_progress'
    or status == 'queued'
    or status == 'pending'
    or status == 'running'
  then
    return 'cancel'
  end
  if status == 'skipped' then
    return nil
  end
  return 'rerun'
end

---@param opts forge.PickerOpts
function M.pick(opts)
  require('forge.picker.fzf').pick(opts)
end

return M
