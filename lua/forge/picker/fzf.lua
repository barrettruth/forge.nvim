local M = {}

local fzf_args = (vim.env.FZF_DEFAULT_OPTS or '')
  :gsub('%-%-bind=[^%s]+', '')
  :gsub('%-%-color=[^%s]+', '')

local no_bg_highlights = {
  ForgeBranch = true,
  ForgeBranchCurrent = true,
  ForgeMerged = true,
}

local special_keys = {
  ['<cr>'] = { fzf = 'enter', header = '<cr>' },
  ['<tab>'] = { fzf = 'tab', header = '<tab>' },
}

local function strip_bg_ansi(text)
  return (text:gsub('\27%[48;2;%d+;%d+;%d+m', ''):gsub('\27%[48;5;%d+m', ''))
end

---@param key string
---@return string
local function to_fzf_key(key)
  local special = special_keys[key]
  if special then
    return special.fzf
  end
  local result = key:gsub('<c%-(%a)>', function(ch)
    return 'ctrl-' .. ch:lower()
  end)
  return result
end

---@param key string
---@return string
local function to_header_key(key)
  local special = special_keys[key]
  if special then
    return special.header
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
      local text = utils.ansi_from_hl(seg[2], seg[1])
      if no_bg_highlights[seg[2]] then
        text = strip_bg_ansi(text)
      end
      table.insert(parts, text)
    else
      table.insert(parts, seg[1])
    end
  end
  return table.concat(parts)
end

local function picker_width()
  local utils = require('fzf-lua.utils')
  local win = type(utils.fzf_winobj) == 'function' and utils.fzf_winobj() or nil
  local winid = win and rawget(win, 'fzf_winid') or nil
  if type(winid) == 'number' and winid > 0 then
    local ok, width = pcall(vim.api.nvim_win_get_width, winid)
    if ok and type(width) == 'number' and width > 0 then
      return width
    end
  end
  return require('forge.layout').picker_width()
end

local function entry_display(entry, width)
  local display = rawget(entry, 'render_display')
  if type(display) == 'function' then
    return display(width)
  end
  return entry.display or {}
end

local function render_line(index, entry, width)
  local text = render(entry_display(entry, width))
  if vim.trim(text) == '' then
    return nil
  end
  return ('%s\t%d'):format(text, index)
end

---@param selected string
---@return integer?
local function selected_index(selected)
  return tonumber(
    selected:match('^(%d+)$') or selected:match('^(%d+)%f[\t]') or selected:match('\t(%d+)$')
  )
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
  local entries = opts.entries or {}
  local stream = rawget(opts, 'stream')
  local seed_entries = vim.list_extend({}, entries)
  local actions = vim.deepcopy(opts.actions or {})
  local live_width = stream ~= nil

  if not live_width then
    for _, entry in ipairs(entries) do
      if type(rawget(entry, 'render_display')) == 'function' then
        live_width = true
        break
      end
    end
  end

  if opts.back and keys.back then
    actions[#actions + 1] = {
      name = 'back',
      fn = function()
        opts.back()
      end,
    }
  end

  local lines
  if live_width then
    lines = function(fzf_cb)
      entries = vim.list_extend({}, seed_entries)
      local next_index = 0
      for i, entry in ipairs(entries) do
        next_index = i
        local line = render_line(i, entry, picker_width())
        if line then
          fzf_cb(line)
        end
      end
      if stream then
        stream(function(entry)
          if not entry then
            fzf_cb(nil)
            return
          end
          next_index = next_index + 1
          entries[next_index] = entry
          local line = render_line(next_index, entry, picker_width())
          if line then
            fzf_cb(line)
          end
        end)
      else
        fzf_cb(nil)
      end
    end
  else
    lines = {}
    for i, entry in ipairs(entries) do
      local line = render_line(i, entry)
      if line then
        lines[#lines + 1] = line
      end
    end
  end

  local fzf_actions = {}
  for _, def in ipairs(actions) do
    local key = def.name == 'default' and '<cr>'
      or def.name == 'back' and keys.back
      or bindings[def.name]
    if key then
      local action_fn = function(selected)
        if not selected[1] then
          def.fn(nil)
          return
        end
        local idx = selected_index(selected[1])
        local entry = picker_mod.selected(idx and entries[idx] or nil)
        if picker_mod.closes(def, entry) and not picker_mod.closes(def) then
          local utils = require('fzf-lua.utils')
          local win = type(utils.fzf_winobj) == 'function' and utils.fzf_winobj() or nil
          if win and type(win.close) == 'function' then
            win:close()
          end
          if type(utils.clear_CTX) == 'function' then
            utils.clear_CTX()
          end
          vim.schedule(function()
            def.fn(entry)
          end)
          return
        end
        def.fn(entry)
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
      ['--header'] = render_header(actions, bindings),
      ['--no-multi'] = '',
      ['--with-nth'] = '1',
      ['--accept-nth'] = '2',
      ['--delimiter'] = '\t',
    },
    actions = fzf_actions,
  })
end

return M
