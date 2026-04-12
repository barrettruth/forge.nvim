local M = {}

local function flatten_display(entry)
  local parts = {}
  for _, seg in ipairs(entry.display or {}) do
    parts[#parts + 1] = seg[1]
  end
  return table.concat(parts)
end

local function action_choices(actions, entry)
  local picker = require('forge.picker')
  local choices = {}
  for _, def in ipairs(actions or {}) do
    if def.label and picker.selected(entry) ~= nil then
      choices[#choices + 1] = def
    end
  end
  return choices
end

---@param opts forge.PickerOpts
function M.pick(opts)
  local entries = opts.entries or {}
  local actions = vim.deepcopy(opts.actions or {})
  local cfg = require('forge').config()
  local keys = cfg.keys == false and {} or (cfg.keys or {})

  if opts.back and keys.back then
    actions[#actions + 1] = {
      name = 'back',
      label = 'back',
      fn = function()
        opts.back()
      end,
    }
  end

  vim.ui.select(entries, {
    prompt = opts.prompt or '',
    format_item = function(entry)
      return flatten_display(entry)
    end,
  }, function(entry)
    if not entry then
      return
    end
    local selected = require('forge.picker').selected(entry)
    local choices = action_choices(actions, entry)
    if #choices <= 1 then
      local action = choices[1] or actions[1]
      if action then
        action.fn(selected)
      end
      return
    end
    vim.ui.select(choices, {
      prompt = (opts.prompt or '') .. 'Action> ',
      format_item = function(action)
        return action.label or action.name
      end,
    }, function(action)
      if action then
        action.fn(selected)
      end
    end)
  end)
end

return M
