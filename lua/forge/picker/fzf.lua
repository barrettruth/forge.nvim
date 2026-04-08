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

---@param key string
---@return string
local function to_header_key(key)
  if key == '<cr>' then
    return '<cr>'
  end
  local ctrl = key:match('^<c%-(.)>$')
  if ctrl then
    return '^' .. ctrl:upper()
  end
  return key
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

---@param actions forge.PickerActionDef[]
---@param bindings table<string, string|false>
---@return string?
local function render_header(actions, bindings)
  local utils = require('fzf-lua.utils')
  local parts = {}
  local seen_keys = {}
  for _, def in ipairs(actions) do
    local key = def.name == 'default' and '<cr>' or bindings[def.name]
    local header_key = key and to_header_key(key) or nil
    if header_key and def.label and not seen_keys[header_key] then
      seen_keys[header_key] = true
      table.insert(
        parts,
        ('%s %s'):format(
          utils.ansi_from_hl('FzfLuaHeaderBind', header_key),
          utils.ansi_from_hl('FzfLuaHeaderText', def.label)
        )
      )
    end
  end
  if #parts < 2 then
    return nil
  end
  return table.concat(parts, '|')
end

---@param opts forge.PickerOpts
function M.pick(opts)
  local cfg = require('forge').config()
  local keys = cfg.keys
  if keys == false then
    keys = {}
  end
  local picker_mod = require('forge.picker')
  local bindings = keys[opts.picker_name] or {}

  local lines = {}
  for i, entry in ipairs(opts.entries) do
    lines[i] = ('%d\t%s'):format(i, render(entry.display))
  end

  local fzf_actions = {}
  for _, def in ipairs(opts.actions) do
    local key = def.name == 'default' and '<cr>' or bindings[def.name]
    if key then
      local action_fn = function(selected)
        if not selected[1] then
          def.fn(nil)
          return
        end
        local idx = tonumber(selected[1]:match('^(%d+)'))
        def.fn(picker_mod.selected(idx and opts.entries[idx] or nil))
      end
      if picker_mod.closes(def) then
        fzf_actions[to_fzf_key(key)] = action_fn
      else
        fzf_actions[to_fzf_key(key)] = { fn = action_fn, reload = true }
      end
    end
  end

  require('fzf-lua').fzf_exec(lines, {
    fzf_args = fzf_args,
    prompt = opts.prompt or '',
    fzf_opts = {
      ['--ansi'] = '',
      ['--header'] = render_header(opts.actions, bindings),
      ['--no-multi'] = '',
      ['--with-nth'] = '2..',
      ['--delimiter'] = '\t',
    },
    actions = fzf_actions,
  })
end

return M
