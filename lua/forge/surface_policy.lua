local ci = require('forge.ci')
local picker_entry = require('forge.picker.entry')

local M = {}

---@param entry forge.PickerEntry?
---@return forge.PickerEntry?
function M.selected(entry)
  if entry and rawget(entry, 'placeholder') then
    return nil
  end
  return entry
end

---@param entry forge.PickerEntry?
---@return forge.PickerRowKind
function M.row_kind(entry)
  if entry == nil then
    return 'none'
  end
  if rawget(entry, 'load_more') then
    return 'load_more'
  end
  if rawget(entry, 'placeholder') then
    return rawget(entry, 'placeholder_kind') == 'error' and 'error' or 'empty'
  end
  return 'entity'
end

---@param entry forge.PickerEntry?
---@return 'close'|'reopen'?
local function toggle_verb_for_state(entry)
  local value = picker_entry.value(entry)
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

function M.closes(def, entry)
  if entry and entry.keep_open then
    return false
  end
  if entry and entry.force_close then
    return true
  end
  return rawget(def, 'close') ~= false
end

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

function M.has_dynamic_label(def)
  return type(rawget(def, 'label')) == 'function' or type(rawget(def, 'available')) == 'function'
end

---@param entry forge.PickerEntry?
---@return forge.ToggleVerb?
function M.issue_toggle_verb(entry)
  return toggle_verb_for_state(entry)
end

---@param entry forge.PickerEntry?
---@return forge.ToggleVerb?
function M.pr_toggle_verb(entry)
  return toggle_verb_for_state(entry)
end

---@param entry forge.PickerEntry?
---@return forge.ToggleVerb?
function M.ci_toggle_verb(entry)
  local value = picker_entry.value(entry)
  if not value then
    return nil
  end
  return ci.toggle_verb(value)
end

return M
