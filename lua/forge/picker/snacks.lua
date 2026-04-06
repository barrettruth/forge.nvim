local M = {}

---@param opts forge.PickerOpts
function M.pick(opts)
  local Snacks = require('snacks')
  local picker_mod = require('forge.picker')

  local cfg = require('forge').config()
  local keys = cfg.keys
  if keys == false then
    keys = {}
  end
  local bindings = keys[opts.picker_name] or {}

  local items = {}
  for i, entry in ipairs(opts.entries) do
    items[i] = {
      idx = i,
      text = picker_mod.ordinal(entry),
      value = entry,
    }
  end

  local snacks_actions = {}
  local input_keys = {}
  local list_keys = {}
  for _, def in ipairs(opts.actions) do
    local key = def.name == 'default' and '<cr>' or bindings[def.name]
    if key then
      local action_name = 'forge_' .. def.name
      snacks_actions[action_name] = function(picker)
        local item = picker:current()
        picker:close()
        def.fn(picker_mod.selected(item and item.value or nil))
      end
      if key == '<cr>' then
        snacks_actions['confirm'] = snacks_actions[action_name]
      else
        -- selene: allow(mixed_table)
        input_keys[key] = { action_name, mode = { 'i', 'n' } }
        list_keys[key] = action_name
      end
    end
  end

  Snacks.picker({
    items = items,
    prompt = opts.prompt,
    format = function(item)
      local ret = {}
      for _, seg in ipairs(item.value.display) do
        table.insert(ret, { seg[1], seg[2] or 'Normal' })
      end
      return ret
    end,
    actions = snacks_actions,
    win = {
      input = { keys = input_keys },
      list = { keys = list_keys },
    },
  })
end

return M
