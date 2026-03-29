local M = {}

local fzf_args = (vim.env.FZF_DEFAULT_OPTS or '')
  :gsub('%-%-bind=[^%s]+', '')
  :gsub('%-%-color=[^%s]+', '')

---@param key string
---@return string
local function to_fzf_key(key)
  if key == '<cr>' then
    return 'default'
  end
  local result = key:gsub('<c%-(%a)>', function(ch)
    return 'ctrl-' .. ch:lower()
  end)
  return result
end

---@param segments forge.Segment[]
---@return string
local function render(segments)
  local utils = require('fzf-lua.utils')
  local parts = {}
  for _, seg in ipairs(segments) do
    if seg[2] then
      table.insert(parts, (utils.ansi_from_hl(seg[2], seg[1])))
    else
      table.insert(parts, seg[1])
    end
  end
  return table.concat(parts)
end

---@param opts forge.PickerOpts
function M.pick(opts)
  local cfg = require('forge').config()
  local keys = cfg.keys
  if keys == false then
    keys = {}
  end
  local bindings = keys[opts.picker_name] or {}

  local lines = {}
  for i, entry in ipairs(opts.entries) do
    lines[i] = ('%d\t%s'):format(i, render(entry.display))
  end

  local fzf_actions = {}
  for _, def in ipairs(opts.actions) do
    local key = def.name == 'default' and '<cr>' or bindings[def.name]
    if key then
      fzf_actions[to_fzf_key(key)] = function(selected)
        if not selected[1] then
          def.fn(nil)
          return
        end
        local idx = tonumber(selected[1]:match('^(%d+)'))
        def.fn(idx and opts.entries[idx] or nil)
      end
    end
  end

  require('fzf-lua').fzf_exec(lines, {
    fzf_args = fzf_args,
    prompt = opts.prompt or '',
    fzf_opts = {
      ['--ansi'] = '',
      ['--no-multi'] = '',
      ['--with-nth'] = '2..',
      ['--delimiter'] = '\t',
    },
    actions = fzf_actions,
  })
end

return M
