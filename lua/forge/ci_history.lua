local M = {}

local layout = require('forge.layout')
local log = require('forge.logger')
local scope_mod = require('forge.scope')
local system_mod = require('forge.system')

local ns = vim.api.nvim_create_namespace('forge_ci_history')

---@class forge.CIHistoryHighlight
---@field col integer
---@field end_col integer
---@field group string

---@class forge.CIHistoryLine
---@field text string
---@field highlights forge.CIHistoryHighlight[]
---@field run forge.CIRun?

---@type table<integer, { proc?: table, request_id?: integer, lines?: forge.CIHistoryLine[], limit?: integer, limit_step?: integer, has_more?: boolean }>
local buf_data = {}

---@param f forge.Forge
---@return string
local function ci_inline_label(f)
  return (f.labels and f.labels.ci_inline) or 'runs'
end

---@param head forge.HeadRef
---@return string?
local function bufname(head)
  local prefix = scope_mod.bufpath(head.scope)
  if not prefix or not head.branch or head.branch == '' then
    return nil
  end
  return ('forge://%s/ci/branch/%s'):format(prefix, head.branch)
end

local function data_for(buf)
  local data = buf_data[buf]
  if not data then
    data = {}
    buf_data[buf] = data
  end
  return data
end

local function set_data(buf, fields)
  local data = data_for(buf)
  for key, value in pairs(fields) do
    data[key] = value
  end
  return data
end

---@param buf integer
---@param kind forge.BufferKind
---@param url string?
local function set_public_buffer_state(buf, kind, url)
  vim.b[buf].forge = {
    version = 1,
    kind = kind,
    url = type(url) == 'string' and url or '',
  }
end

local function stop_proc(buf)
  local proc = data_for(buf).proc
  if proc and type(proc.kill) == 'function' then
    pcall(function()
      proc:kill()
    end)
  end
  data_for(buf).proc = nil
end

local function begin_request(buf)
  local data = data_for(buf)
  data.request_id = (data.request_id or 0) + 1
  stop_proc(buf)
  return data.request_id
end

local function request_current(buf, request_id)
  return data_for(buf).request_id == request_id
end

local function limit_settings(buf, opts)
  local cfg = require('forge').config()
  local step = cfg.display and cfg.display.limits and cfg.display.limits.runs or 30
  if type(step) ~= 'number' or step < 1 then
    step = 30
  end
  local limit = type(opts) == 'table' and opts.limit or nil
  if type(limit) ~= 'number' or limit < 1 then
    limit = data_for(buf).limit
  end
  if type(limit) ~= 'number' or limit < 1 then
    limit = step
  end
  limit = math.max(step, math.floor(limit))
  return step, limit
end

local function line_positions(buf)
  local lines = data_for(buf).lines or {}
  local positions = {}
  for lnum, line in ipairs(lines) do
    if line.run ~= nil then
      positions[#positions + 1] = lnum
    end
  end
  return positions
end

local function jump(buf, dir)
  local positions = line_positions(buf)
  if #positions == 0 then
    return
  end
  local current = vim.api.nvim_win_get_cursor(0)[1]
  if dir > 0 then
    for _, lnum in ipairs(positions) do
      if lnum > current then
        vim.api.nvim_win_set_cursor(0, { lnum, 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(0, { positions[1], 0 })
    return
  end
  for i = #positions, 1, -1 do
    if positions[i] < current then
      vim.api.nvim_win_set_cursor(0, { positions[i], 0 })
      return
    end
  end
  vim.api.nvim_win_set_cursor(0, { positions[#positions], 0 })
end

---@param buf integer
---@return forge.CIRun?
local function current_run(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = data_for(buf).lines or {}
  local entry = lines[line]
  return entry and entry.run or nil
end

---@param run forge.CIRun
---@return forge.RunRef
local function run_ref(run)
  return {
    id = run.id,
    scope = run.scope,
    status = run.status,
    url = run.url,
  }
end

---@param runs forge.CIRun[]
---@return forge.CIHistoryLine[]
local function render_rows(runs)
  local forge = require('forge')
  local rows = forge.format_runs(runs, { width = layout.picker_width() })
  local lines = {}
  for index, row in ipairs(rows) do
    local text = {}
    local highlights = {}
    local col = 0
    for _, seg in ipairs(row) do
      local part = seg[1] or ''
      text[#text + 1] = part
      if seg[2] then
        highlights[#highlights + 1] = {
          col = col,
          end_col = col + #part,
          group = seg[2],
        }
      end
      col = col + #part
    end
    local line_text = table.concat(text):gsub('%s+$', '')
    local end_col = #line_text
    for i = #highlights, 1, -1 do
      local hl = highlights[i]
      if hl.col >= end_col then
        table.remove(highlights, i)
      elseif hl.end_col > end_col then
        hl.end_col = end_col
      end
    end
    lines[#lines + 1] = {
      text = line_text,
      highlights = highlights,
      run = runs[index],
    }
  end
  return lines
end

---@param text string
---@param group string?
---@return forge.CIHistoryLine[]
local function render_placeholder(text, group)
  return {
    {
      text = text,
      highlights = group and {
        {
          col = 0,
          end_col = #text,
          group = group,
        },
      } or {},
      run = nil,
    },
  }
end

local function pager_line(label, visible_count, limit_step, limit, has_more)
  local actions = {}
  if has_more then
    actions[#actions + 1] = ']c older ' .. label
  end
  if limit > limit_step then
    actions[#actions + 1] = '[c fewer ' .. label
  end
  if #actions == 0 then
    return nil
  end
  local prefix
  if has_more then
    prefix = ('Showing newest %d %s'):format(visible_count, label)
  else
    prefix = ('Showing %d %s'):format(visible_count, label)
  end
  local text = prefix .. ' · ' .. table.concat(actions, ' · ')
  return {
    text = text,
    highlights = {
      {
        col = 0,
        end_col = #text,
        group = 'ForgeDim',
      },
    },
    run = nil,
  }
end

---@param buf integer
---@param lines forge.CIHistoryLine[]
local function render(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(
    buf,
    0,
    -1,
    false,
    vim.tbl_map(function(line)
      return line.text
    end, lines)
  )
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for lnum, line in ipairs(lines) do
    for _, hl in ipairs(line.highlights or {}) do
      vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, hl.col, {
        end_col = hl.end_col,
        hl_group = hl.group,
      })
    end
  end
  set_data(buf, { lines = lines })
end

---@param f forge.Forge
---@param runs table[]
---@param scope forge.Scope?
---@return forge.CIRun[]
local function normalize_runs(f, runs, scope)
  local forge = require('forge')
  local normalized = {}
  for _, entry in ipairs(runs) do
    local run = f:normalize_run(entry)
    run.scope = run.scope or scope
    normalized[#normalized + 1] = run
  end
  return forge.filter_runs(normalized, 'all')
end

---@param buf integer
---@param f forge.Forge
---@param head forge.HeadRef
---@param opts table?
local function setup_keymaps(buf, f, head, opts)
  local cfg = require('forge').config()
  local ci_keys = type(cfg.keys) == 'table' and cfg.keys.ci or {}
  local log_keys = type(cfg.keys) == 'table' and cfg.keys.log or {}
  local function reopen(limit)
    local next_opts = vim.tbl_extend('force', {}, opts or {})
    next_opts.limit = limit
    M.open(f, head, next_opts, buf)
  end
  local function map(key, fn, desc)
    if key and key ~= false then
      vim.keymap.set('n', key, fn, { buffer = buf, desc = desc })
    end
  end
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf, desc = 'Close' })
  vim.keymap.set('n', 'gx', function()
    local run = current_run(buf)
    if run then
      require('forge.ops').ci_browse(f, run_ref(run))
    end
  end, { buffer = buf, desc = 'Browse' })
  vim.keymap.set('n', '<cr>', function()
    local run = current_run(buf)
    if run then
      require('forge.ops').ci_open(f, run_ref(run))
    end
  end, { buffer = buf, desc = 'Open' })
  map(ci_keys.refresh, function()
    M.open(f, head, opts, buf)
  end, 'Refresh')
  map(log_keys.next_step, function()
    jump(buf, 1)
  end, 'Next run')
  map(log_keys.prev_step, function()
    jump(buf, -1)
  end, 'Previous run')
  vim.keymap.set('n', ']c', function()
    local step, limit = limit_settings(buf)
    reopen(limit + step)
  end, { buffer = buf, desc = 'Older runs' })
  vim.keymap.set('n', '[c', function()
    local step, limit = limit_settings(buf)
    if limit <= step then
      return
    end
    reopen(math.max(step, limit - step))
  end, { buffer = buf, desc = 'Newer runs' })
end

---@param head forge.HeadRef
---@param reuse_buf integer?
---@return integer, boolean
local function prepare_buf(head, reuse_buf)
  local name = bufname(head)
  local buf
  local reusing = false
  if reuse_buf and vim.api.nvim_buf_is_valid(reuse_buf) then
    buf = reuse_buf
    reusing = true
  else
    local existing = name and vim.fn.bufnr(name) or -1
    if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
      buf = existing
      reusing = true
      local wins = vim.fn.win_findbuf(buf)
      if #wins == 0 then
        local cfg = require('forge').config()
        local split = cfg.ci.split or cfg.split
        local prefix = split == 'vertical' and 'vertical' or 'botright'
        vim.cmd('noautocmd ' .. prefix .. ' sbuffer ' .. buf)
      end
    else
      local cfg = require('forge').config()
      local split = cfg.ci.split or cfg.split
      local prefix = split == 'vertical' and 'vertical' or 'botright'
      vim.cmd('noautocmd ' .. prefix .. ' new')
      buf = vim.api.nvim_get_current_buf()
      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.bo[buf].swapfile = false
      vim.bo[buf].modifiable = false
      if name then
        vim.api.nvim_buf_set_name(buf, name)
      end
      vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = buf,
        callback = function()
          stop_proc(buf)
          buf_data[buf] = nil
        end,
      })
    end
  end
  vim.bo[buf].filetype = 'forgelist'
  set_public_buffer_state(buf, 'ci_history', scope_mod.branch_web_url(head.scope, head.branch))
  if not reusing then
    render(buf, render_placeholder('Loading...', 'ForgeDim'))
  end
  return buf, reusing
end

---@param f forge.Forge
---@param head forge.HeadRef
---@param opts table?
---@param reuse_buf integer?
function M.open(f, head, opts, reuse_buf)
  opts = opts or {}
  local buf, reusing = prepare_buf(head, reuse_buf)
  local saved_cursor
  local limit_step, limit = limit_settings(buf, opts)
  if reusing then
    local wins = vim.fn.win_findbuf(buf)
    if #wins > 0 then
      saved_cursor = vim.api.nvim_win_get_cursor(wins[1])
    end
  end
  if not reusing then
    setup_keymaps(buf, f, head, opts)
  end
  set_data(buf, {
    limit = limit,
    limit_step = limit_step,
  })
  local request_id = begin_request(buf)
  local cmd = f:list_runs_json_cmd(head.branch, head.scope, limit + 1)
  log.debug(('fetching %s for %s...'):format(ci_inline_label(f), head.branch))
  local proc = vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) or not request_current(buf, request_id) then
        return
      end
      local stdout = result.stdout or ''
      if result.code ~= 0 or stdout == '' then
        local msg = system_mod.cmd_error(result, ('failed to fetch %s'):format(ci_inline_label(f)))
        render(buf, render_placeholder(msg, 'ForgeFail'))
        log.error(msg)
        return
      end
      local ok, decoded = pcall(vim.json.decode, stdout)
      if not ok or type(decoded) ~= 'table' then
        local msg = ('failed to parse %s details'):format(ci_inline_label(f))
        render(buf, render_placeholder(msg, 'ForgeFail'))
        log.error(msg)
        return
      end
      local runs = normalize_runs(f, decoded, head.scope)
      if #runs == 0 then
        render(
          buf,
          render_placeholder(('No %s for %s'):format(ci_inline_label(f), head.branch), 'ForgeDim')
        )
        return
      end
      local has_more = #runs > limit
      if has_more then
        runs = vim.list_slice(runs, 1, limit)
      end
      local lines = render_rows(runs)
      local pager = pager_line(ci_inline_label(f), #runs, limit_step, limit, has_more)
      if pager then
        lines[#lines + 1] = pager
      end
      render(buf, lines)
      set_data(buf, {
        has_more = has_more,
      })
      if saved_cursor then
        local wins = vim.fn.win_findbuf(buf)
        if #wins > 0 then
          saved_cursor[1] = math.min(saved_cursor[1], vim.api.nvim_buf_line_count(buf))
          vim.api.nvim_win_set_cursor(wins[1], saved_cursor)
        end
      end
    end)
  end)
  set_data(buf, { proc = proc })
end

return M
