local M = {}

---@alias forge.Segment {[1]: string, [2]: string?}

---@class forge.PickerEntry
---@field display forge.Segment[]
---@field value any
---@field ordinal string?

---@class forge.PickerActionDef
---@field name string
---@field fn fun(entry: forge.PickerEntry?)

---@class forge.PickerOpts
---@field prompt string?
---@field entries forge.PickerEntry[]
---@field actions forge.PickerActionDef[]
---@field picker_name string

---@type table<string, string>
local backends = {
  ['fzf-lua'] = 'forge.picker.fzf',
  telescope = 'forge.picker.telescope',
  snacks = 'forge.picker.snacks',
}

---@return string
local function detect()
  local cfg = require('forge').config()
  local name = cfg.picker or 'auto'
  if name ~= 'auto' then
    return name
  end
  if pcall(require, 'fzf-lua') then
    return 'fzf-lua'
  end
  if pcall(require, 'snacks') then
    return 'snacks'
  end
  if pcall(require, 'telescope') then
    return 'telescope'
  end
  return 'fzf-lua'
end

---@param entry forge.PickerEntry
---@return string
function M.ordinal(entry)
  if entry.ordinal then
    return entry.ordinal
  end
  local parts = {}
  for _, seg in ipairs(entry.display) do
    table.insert(parts, seg[1])
  end
  return table.concat(parts)
end

---@return string
function M.backend()
  return detect()
end

---@param opts forge.PickerOpts
function M.pick(opts)
  local name = detect()
  local mod_path = backends[name]
  if not mod_path then
    vim.notify('[forge]: unknown picker backend: ' .. name, vim.log.levels.ERROR)
    return
  end
  local ok, backend = pcall(require, mod_path)
  if not ok then
    vim.notify('[forge]: picker backend ' .. name .. ' not available', vim.log.levels.ERROR)
    return
  end
  backend.pick(opts)
end

return M
