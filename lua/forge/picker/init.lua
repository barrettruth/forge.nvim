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

---@class forge.PickerActionDef
---@field name string
---@field label forge.PickerActionLabel?
---@field close boolean?
---@field fn fun(entry: forge.PickerEntry?)

---@class forge.PickerOpts
---@field prompt string?
---@field entries forge.PickerEntry[]
---@field actions forge.PickerActionDef[]
---@field picker_name string
---@field back fun()?
---@field entry_source? fun(): forge.PickerEntry[]?
---@field initial_stream_only? boolean

M.backends = {
  ['fzf-lua'] = 'forge.picker.fzf',
}

M.detect_order = { 'fzf-lua' }

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

---@return string
local function detect()
  local cfg = require('forge').config()
  local name = cfg.picker or 'auto'
  if name ~= 'auto' then
    return name
  end
  for _, backend in ipairs(M.detect_order) do
    if pcall(require, backend) then
      return backend
    end
  end
  return M.detect_order[1]
end

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

---@return string
function M.backend()
  return detect()
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
---@return string?
function M.resolve_label(def, entry)
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
  return type(rawget(def, 'label')) == 'function'
end

local function ci_verb(status)
  status = (status or ''):lower()
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

local function pr_verb(state)
  state = (state or ''):lower()
  if state == 'open' or state == 'opened' then
    return 'close'
  end
  if state == 'closed' then
    return 'reopen'
  end
  return nil
end

local function issue_verb(state)
  state = (state or ''):lower()
  if state == 'open' or state == 'opened' then
    return 'close'
  end
  if state == 'closed' then
    return 'reopen'
  end
  return nil
end

---@param picker_name string
---@param entry forge.PickerEntry?
---@return string?
function M.toggle_verb(picker_name, entry)
  if not entry or rawget(entry, 'placeholder') or rawget(entry, 'load_more') then
    return nil
  end
  local value = entry.value
  if type(value) ~= 'table' then
    return nil
  end
  if picker_name == 'pr' then
    return pr_verb(value.state)
  end
  if picker_name == 'issue' then
    return issue_verb(value.state)
  end
  if picker_name == 'ci' then
    return ci_verb(value.status)
  end
  return nil
end

---@param opts forge.PickerOpts
function M.pick(opts)
  local name = detect()
  local mod_path = M.backends[name]
  if not mod_path then
    require('forge.logger').error('unknown picker backend: ' .. name)
    return
  end
  local ok, backend = pcall(require, mod_path)
  if not ok then
    require('forge.logger').error('picker backend ' .. name .. ' not available')
    return
  end
  backend.pick(opts)
end

return M
