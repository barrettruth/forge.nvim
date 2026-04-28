local M = {}

local detect = require('forge.detect')
local surface = require('forge.surface')

local function has_fzf()
  return pcall(require, 'fzf-lua')
end

---@alias forge.Segment {[1]: string, [2]: string?}

---@class forge.PickerEntry
---@field display forge.Segment[]
---@field value any
---@field ordinal string?
---@field placeholder boolean?
---@field placeholder_kind? 'empty'|'error'
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

---@class forge.PickerHandle
---@field refresh fun(): boolean?

---@class forge.PickerOpts
---@field prompt string?
---@field entries forge.PickerEntry[]
---@field actions forge.PickerActionDef[]
---@field header_order? string[]
---@field picker_name string
---@field back fun()?
---@field stream? fun(emit: fun(entry: forge.PickerEntry?))

---@class forge.PickerHint
---@field name string
---@field key string
---@field label string
---@field index integer?

---@type table<string, string[]>
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

---@param entry forge.PickerEntry
---@return string
local function flatten_display(entry)
  local parts = {}
  for _, seg in ipairs(entry.display or {}) do
    parts[#parts + 1] = seg[1]
  end
  return table.concat(parts)
end

---@param parts string[]
---@return string
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

---@param entry forge.PickerEntry
---@return string
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
    local forge_name = detect.forge_name()
    local resolved = surface.resolve_section(value, forge_name)
      or surface.resolve_route(value, forge_name)
    local lookup = resolved and resolved.canonical or value
    local root_terms = root_search_terms[lookup]
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
      return join_search_terms({ value.name or '', value.context or '', value.branch or '' })
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

---@param hints forge.PickerHint[]
---@param order? string[]
---@return forge.PickerHint[]
function M.order_hints(hints, order)
  local ranks = {}
  for index, name in ipairs(order or {}) do
    if type(name) == 'string' and ranks[name] == nil then
      ranks[name] = index
    end
  end

  local sorted = {}
  for index, hint in ipairs(hints or {}) do
    if type(hint) == 'table' and type(hint.name) == 'string' and type(hint.key) == 'string' then
      sorted[#sorted + 1] = vim.tbl_extend('keep', { index = index }, hint)
    end
  end

  table.sort(sorted, function(a, b)
    local a_rank = ranks[a.name] or math.huge
    local b_rank = ranks[b.name] or math.huge
    if a_rank ~= b_rank then
      return a_rank < b_rank
    end
    return (a.index or 0) < (b.index or 0)
  end)

  local ordered = {}
  local seen_keys = {}
  for _, hint in ipairs(sorted) do
    if not seen_keys[hint.key] then
      seen_keys[hint.key] = true
      ordered[#ordered + 1] = hint
    end
  end
  return ordered
end

---@return boolean
function M.ui_available()
  return has_fzf()
end

---@return string
function M.unavailable_message()
  return "fzf-lua not found (interactive routes and require('forge.picker').pick() disabled; direct :Forge commands and deterministic Lua helpers still available)"
end

---@param opts forge.PickerOpts
---@return forge.PickerHandle?
function M.pick(opts)
  if not M.ui_available() then
    require('forge.logger').warn(M.unavailable_message())
    return nil
  end
  return require('forge.picker.fzf').pick(opts)
end

return M
