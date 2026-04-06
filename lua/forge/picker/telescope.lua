local M = {}

---@param opts forge.PickerOpts
function M.pick(opts)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local picker_mod = require('forge.picker')

  local cfg = require('forge').config()
  local keys = cfg.keys
  if keys == false then
    keys = {}
  end
  local bindings = keys[opts.picker_name] or {}

  local finder = finders.new_table({
    results = opts.entries,
    entry_maker = function(entry)
      return {
        value = entry,
        ordinal = picker_mod.ordinal(entry),
        display = function(tbl)
          local text = ''
          local hl_list = {}
          for _, seg in ipairs(tbl.value.display) do
            local start = #text
            text = text .. seg[1]
            if seg[2] then
              table.insert(hl_list, { { start, #text }, seg[2] })
            end
          end
          return text, hl_list
        end,
      }
    end,
  })

  pickers
    .new({}, {
      prompt_title = (opts.prompt or ''):gsub('[>%s]+$', ''),
      finder = finder,
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        for _, def in ipairs(opts.actions) do
          local key = def.name == 'default' and '<cr>' or bindings[def.name]
          if key then
            local function action_fn()
              local entry = action_state.get_selected_entry()
              if picker_mod.closes(def) then
                actions.close(prompt_bufnr)
              end
              def.fn(picker_mod.selected(entry and entry.value or nil))
            end
            if key == '<cr>' then
              actions.select_default:replace(action_fn)
            else
              map('i', key, action_fn)
              map('n', key, action_fn)
            end
          end
        end
        return true
      end,
    })
    :find()
end

return M
