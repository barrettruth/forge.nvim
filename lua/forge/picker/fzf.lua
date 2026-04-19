local M = {}

local fzf_args = (vim.env.FZF_DEFAULT_OPTS or '')
  :gsub('%-%-bind=[^%s]+', '')
  :gsub('%-%-color=[^%s]+', '')

local special_keys = {
  ['<cr>'] = { fzf = 'enter', header = '<cr>' },
  ['<tab>'] = { fzf = 'tab', header = '<tab>' },
}

local function strip_bg_ansi(text)
  return (text:gsub('\27%[48;2;%d+;%d+;%d+m', ''):gsub('\27%[48;5;%d+m', ''))
end

local function header_hls()
  local ok, config = pcall(require, 'fzf-lua.config')
  local globals = ok and type(config.globals) == 'table' and config.globals or nil
  local hls = type(globals) == 'table' and (globals.hls or globals.__HLS) or nil
  local fzf_hls = type(hls) == 'table' and hls.fzf or nil
  return {
    bind = type(hls) == 'table' and hls.header_bind or 'FzfLuaHeaderBind',
    text = type(hls) == 'table' and hls.header_text or 'FzfLuaHeaderText',
    separator = type(fzf_hls) == 'table' and fzf_hls.info or 'FzfLuaFzfInfo',
  }
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
      text = strip_bg_ansi(text)
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

local function track_id(entry, index)
  local explicit = rawget(entry, 'track_id')
  if type(explicit) == 'string' and explicit ~= '' then
    return explicit
  end
  if entry.load_more then
    return '__load_more__:' .. tostring(rawget(entry, 'next_limit') or index)
  end
  if entry.placeholder then
    return '__placeholder__:' .. (entry.ordinal or tostring(index))
  end
  local value = entry.value
  if type(value) == 'string' or type(value) == 'number' then
    return tostring(value)
  end
  if type(value) == 'table' then
    for _, key in ipairs({ 'id', 'num', 'tag', 'sha', 'path', 'name', 'run_id' }) do
      local item = rawget(value, key)
      if item ~= nil and tostring(item) ~= '' then
        return tostring(item)
      end
    end
  end
  if type(entry.ordinal) == 'string' and entry.ordinal ~= '' then
    return entry.ordinal
  end
  return tostring(index)
end

---@param index integer
---@param entry forge.PickerEntry
---@param width integer?
---@param tracked boolean
---@param header_text string?
---@return string?
local function render_line(index, entry, width, tracked, header_text)
  local text = render(entry_display(entry, width))
  if vim.trim(text) == '' then
    return nil
  end
  if tracked then
    if header_text then
      return ('%s\t%s\t%d\t%s'):format(track_id(entry, index), text, index, header_text)
    end
    return ('%s\t%s\t%d'):format(track_id(entry, index), text, index)
  end
  if header_text then
    return ('%s\t%d\t%s'):format(text, index, header_text)
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
---@param entry forge.PickerEntry?
---@return string?
local function render_header_for(actions, bindings, entry)
  local picker_mod = require('forge.picker')
  local utils = require('fzf-lua.utils')
  local hls = header_hls()
  local parts = {}
  local seen_keys = {}
  for _, def in ipairs(actions) do
    local key = def.name == 'default' and '<cr>' or bindings[def.name]
    local header_key = key and to_header_key(key) or nil
    local label = header_key and picker_mod.resolve_label(def, entry) or nil
    if header_key and label and not seen_keys[header_key] then
      seen_keys[header_key] = true
      table.insert(
        parts,
        ('%s %s'):format(
          utils.ansi_from_hl(hls.bind, header_key),
          utils.ansi_from_hl(hls.text, label)
        )
      )
    end
  end
  if #parts < 2 then
    return nil
  end
  local separator = utils.ansi_from_hl(hls.separator, '|')
  return table.concat(parts, separator)
end

---@param actions forge.PickerActionDef[]
---@param bindings table<string, string|false>
---@return string?
local function render_header(actions, bindings)
  return render_header_for(actions, bindings, nil)
end

---@param actions forge.PickerActionDef[]
---@return boolean
local function has_dynamic_label(actions)
  local picker_mod = require('forge.picker')
  for _, def in ipairs(actions) do
    if picker_mod.has_dynamic_label(def) then
      return true
    end
  end
  return false
end

---@param text string?
---@return string?
local function sanitize_header(text)
  if type(text) ~= 'string' then
    return nil
  end
  return (text:gsub('\t', ' '):gsub('\r', ' '):gsub('\n', ' '))
end

---@param text string?
---@return string?
local function transport_header(text)
  local sanitized = sanitize_header(text)
  if sanitized == nil then
    return nil
  end
  return (sanitized:gsub('\\', '\\\\'):gsub('\27', '\\033'))
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
  local tracked = stream ~= nil
  local track_redirect

  local function action_reloads(def)
    local explicit = rawget(def, 'reload')
    if explicit ~= nil then
      return explicit == true
    end
    if stream then
      return true
    end
    if not picker_mod.closes(def) then
      return true
    end
    for _, entry in ipairs(seed_entries) do
      if not picker_mod.closes(def, entry) then
        return true
      end
    end
    return false
  end

  if not live_width then
    for _, entry in ipairs(entries) do
      if type(rawget(entry, 'render_display')) == 'function' then
        live_width = true
        break
      end
    end
  end

  if opts.back then
    actions[#actions + 1] = {
      name = 'back',
      reload = false,
      fn = function()
        opts.back()
      end,
    }
  end

  local dynamic_header = has_dynamic_label(actions)
  local header_field = dynamic_header and (tracked and 4 or 3) or nil

  local function entry_header(entry)
    if not dynamic_header then
      return nil
    end
    return transport_header(render_header_for(actions, bindings, entry))
  end

  local initial_header
  if dynamic_header then
    for _, entry in ipairs(entries) do
      if not rawget(entry, 'placeholder') and not rawget(entry, 'load_more') then
        initial_header = render_header_for(actions, bindings, entry)
        break
      end
    end
    if not initial_header then
      initial_header = render_header_for(actions, bindings, nil)
    end
  else
    initial_header = render_header(actions, bindings)
  end

  local lines
  if live_width then
    lines = function(fzf_cb)
      entries = {}
      local next_index = 0
      local function emit(entry)
        if entry == nil then
          fzf_cb(nil)
          return
        end
        next_index = next_index + 1
        if track_redirect and next_index == track_redirect.target_index and not entry.load_more then
          entry = vim.tbl_extend('force', {}, entry, { track_id = track_redirect.source_id })
          track_redirect = nil
        end
        entries[next_index] = entry
        local line = render_line(next_index, entry, picker_width(), tracked, entry_header(entry))
        if line then
          fzf_cb(line)
        end
      end
      if stream then
        stream(emit)
      else
        for _, entry in ipairs(seed_entries) do
          emit(entry)
        end
        emit(nil)
      end
    end
  else
    lines = {}
    for i, entry in ipairs(entries) do
      local line = render_line(i, entry, nil, tracked, entry_header(entry))
      if line then
        lines[#lines + 1] = line
      end
    end
  end

  local fzf_actions = {}
  for _, def in ipairs(actions) do
    local key = def.name == 'default' and '<cr>'
      or def.name == 'back' and '<c-o>'
      or bindings[def.name]
    if key then
      local reloads = action_reloads(def)
      local action_fn = function(selected)
        if not selected[1] then
          if not picker_mod.available(def, nil) then
            return
          end
          if reloads and picker_mod.closes(def) then
            local utils = require('fzf-lua.utils')
            local win = type(utils.fzf_winobj) == 'function' and utils.fzf_winobj() or nil
            if win and type(win.close) == 'function' then
              win:close()
            end
            if type(utils.clear_CTX) == 'function' then
              utils.clear_CTX()
            end
            vim.schedule(function()
              def.fn(nil)
            end)
            return
          end
          def.fn(nil)
          return
        end
        local idx = selected_index(selected[1])
        local entry = picker_mod.selected(idx and entries[idx] or nil)
        if not picker_mod.available(def, entry) then
          return
        end
        if reloads and entry and rawget(entry, 'load_more') and tracked and idx then
          track_redirect = {
            source_id = track_id(entry, idx),
            target_index = idx,
          }
        else
          track_redirect = nil
        end
        if reloads and picker_mod.closes(def, entry) then
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
      if reloads then
        fzf_actions[to_fzf_key(key)] = {
          fn = action_fn,
          reload = true,
          field_index = tracked and '{3}' or '{2}',
        }
      else
        fzf_actions[to_fzf_key(key)] = action_fn
      end
    end
  end

  local fzf_exec_opts = {
    fzf_args = fzf_args,
    no_hide = true,
    no_resume = true,
    prompt = opts.prompt or '',
    fzf_opts = {
      ['--ansi'] = '',
      ['--header'] = initial_header,
      ['--no-multi'] = '',
      ['--with-nth'] = tracked and '2' or '1',
      ['--accept-nth'] = tracked and '3' or '2',
      ['--delimiter'] = '\t',
      ['--track'] = tracked and '' or nil,
      ['--id-nth'] = tracked and '1' or nil,
    },
    actions = fzf_actions,
  }

  if header_field then
    fzf_exec_opts.keymap = {
      fzf = {
        focus = ("transform-header:printf '%%b' {%d}"):format(header_field),
      },
    }
  end

  require('fzf-lua').fzf_exec(lines, fzf_exec_opts)
end

return M
