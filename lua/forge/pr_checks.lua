local M = {}

local layout = require('forge.layout')
local log = require('forge.logger')
local scope_mod = require('forge.scope')
local system_mod = require('forge.system')

local ns = vim.api.nvim_create_namespace('forge_pr_checks')

---@class forge.PRChecksHighlight
---@field col integer
---@field end_col integer
---@field group string

---@class forge.PRChecksLine
---@field text string
---@field highlights forge.PRChecksHighlight[]
---@field check forge.Check?

---@type table<integer, { proc?: table, request_id?: integer, lines?: forge.PRChecksLine[] }>
local buf_data = {}

---@param pr forge.PRRef
---@return string?
local function bufname(pr)
  local prefix = scope_mod.bufpath(pr.scope)
  if not prefix or not pr.num or pr.num == '' then
    return nil
  end
  return ('forge://%s/pr/%s/checks'):format(prefix, pr.num)
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

local function line_positions(buf)
  local lines = data_for(buf).lines or {}
  local positions = {}
  for lnum, line in ipairs(lines) do
    if line.check ~= nil then
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
---@return forge.Check?
local function current_check(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = data_for(buf).lines or {}
  local entry = lines[line]
  return entry and entry.check or nil
end

---@param check forge.Check
---@return string?
local function check_run_id(check)
  return check.run_id or (check.link or ''):match('/actions/runs/(%d+)')
end

---@param check forge.Check
---@return string?
local function check_job_id(check)
  return check.job_id or (check.link or ''):match('/job/(%d+)')
end

local function browseable_check(check)
  return type(check) == 'table' and type(check.link) == 'string' and check.link ~= ''
end

local openable_check
local inspect_check

---@param checks forge.Check[]
---@return forge.PRChecksLine[]
local function render_rows(checks)
  local forge = require('forge')
  local display_checks = {}
  for _, check in ipairs(checks) do
    local label = check.name or ''
    if not openable_check(check) then
      if browseable_check(check) then
        label = label .. ' [web]'
      else
        label = label .. ' [unavailable]'
      end
    end
    display_checks[#display_checks + 1] = vim.tbl_extend('force', {}, check, {
      name = label,
    })
  end
  local rows = forge.format_checks(display_checks, { width = layout.picker_width() })
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
      check = checks[index],
    }
  end
  return lines
end

---@param text string
---@param group string?
---@return forge.PRChecksLine[]
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
      check = nil,
    },
  }
end

---@param buf integer
---@param lines forge.PRChecksLine[]
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

local function normalize_job_filter_input(text)
  if text == nil then
    return nil, true
  end
  local trimmed = vim.trim(text)
  if trimmed == '' then
    return nil, false
  end
  return trimmed, false
end

local function matches_job_filter(name, job_filter)
  if type(job_filter) ~= 'string' or job_filter == '' then
    return true
  end
  local candidate = type(name) == 'string' and name:lower() or ''
  return candidate:find(job_filter:lower(), 1, true) ~= nil
end

---@param check forge.Check?
---@return boolean
openable_check = function(check)
  if type(check) ~= 'table' then
    return false
  end
  if (check.bucket or ''):lower() == 'skipping' then
    return false
  end
  return check_run_id(check) ~= nil
end

local function open_check(f, check, scope)
  if openable_check(check) then
    inspect_check(f, check, scope)
    return
  end
  if browseable_check(check) then
    vim.ui.open(check.link)
  end
end

inspect_check = function(f, check, scope)
  if not openable_check(check) then
    return
  end
  local run_id = check_run_id(check)
  if not run_id then
    return
  end
  local job_id = check_job_id(check)
  local bucket = (check.bucket or ''):lower()
  local ref = check.scope or scope
  local in_progress = bucket == 'pending'
  if in_progress and f.live_tail_cmd then
    require('forge.term').open(f:live_tail_cmd(run_id, job_id, ref), { url = check.link })
    return
  end
  require('forge.log').open(f:check_log_cmd(run_id, bucket == 'fail', job_id, ref), {
    forge_name = f.name,
    scope = ref,
    run_id = run_id,
    url = check.link,
    steps_cmd = f.steps_cmd and f:steps_cmd(run_id, ref) or nil,
    job_id = job_id,
    in_progress = in_progress,
    status_cmd = f.run_status_cmd and f:run_status_cmd(run_id, ref) or nil,
    replace_win = vim.api.nvim_get_current_win(),
  })
end

---@param buf integer
---@param f forge.Forge
---@param pr forge.PRRef
---@param opts table?
local function setup_keymaps(buf, f, pr, opts)
  opts = opts or {}
  local cfg = require('forge').config()
  local keys = type(cfg.keys) == 'table' and cfg.keys.log or {}
  local function map(key, fn, desc)
    if key and key ~= false then
      vim.keymap.set('n', key, fn, { buffer = buf, desc = desc })
    end
  end
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf, desc = 'Close' })
  vim.keymap.set('n', 'gx', function()
    local check = current_check(buf)
    if check and check.link and check.link ~= '' then
      vim.ui.open(check.link)
    end
  end, { buffer = buf, desc = 'Browse' })
  vim.keymap.set('n', '<cr>', function()
    local check = current_check(buf)
    if check then
      open_check(f, check, pr.scope)
    end
  end, { buffer = buf, desc = 'Open' })
  map(keys.filter, function()
    vim.ui.input({ prompt = 'Filter jobs: ', default = opts.job_filter or '' }, function(input)
      local next_filter, cancelled = normalize_job_filter_input(input)
      if cancelled then
        return
      end
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        opts.job_filter = next_filter
        M.open(f, pr, opts, buf)
      end)
    end)
  end, 'Filter jobs')
  map(keys.refresh, function()
    M.open(f, pr, opts, buf)
  end, 'Refresh')
  map(keys.next_step, function()
    jump(buf, 1)
  end, 'Next check')
  map(keys.prev_step, function()
    jump(buf, -1)
  end, 'Previous check')
end

---@param pr forge.PRRef
---@param reuse_buf integer?
---@return integer, boolean
local function prepare_buf(pr, reuse_buf)
  local name = bufname(pr)
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
  set_public_buffer_state(buf, 'pr_checks', scope_mod.subject_web_url('pr', pr.num, pr.scope))
  if not reusing then
    render(buf, render_placeholder('Loading...', 'ForgeDim'))
  end
  return buf, reusing
end

---@param checks forge.Check[]
---@param scope forge.Scope?
---@param job_filter string?
---@return forge.Check[]
local function normalize_checks(checks, scope, job_filter)
  local forge = require('forge')
  local normalized = vim.deepcopy(checks)
  for _, check in ipairs(normalized) do
    check.scope = check.scope or scope
  end
  local filtered = forge.filter_checks(normalized, 'all')
  if type(job_filter) ~= 'string' or job_filter == '' then
    return filtered
  end
  return vim.tbl_filter(function(check)
    return matches_job_filter(check.name, job_filter)
  end, filtered)
end

---@param f forge.Forge
---@param pr forge.PRRef
---@param opts table?
---@param reuse_buf integer?
function M.open(f, pr, opts, reuse_buf)
  opts = opts or {}
  local buf, reusing = prepare_buf(pr, reuse_buf)
  if not reusing then
    setup_keymaps(buf, f, pr, opts)
  end
  local request_id = begin_request(buf)
  local cmd = f:checks_json_cmd(pr.num, pr.scope)
  log.debug(('fetching checks for %s #%s...'):format(f.labels.pr_one, pr.num))
  local proc = vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) or not request_current(buf, request_id) then
        return
      end
      local stdout = result.stdout or ''
      if result.code ~= 0 or stdout == '' then
        local msg = system_mod.cmd_error(
          result,
          ('failed to fetch checks for %s #%s'):format(f.labels.pr_one, pr.num)
        )
        render(buf, render_placeholder(msg, 'ForgeFail'))
        log.error(msg)
        return
      end
      local ok, decoded = pcall(vim.json.decode, stdout)
      if not ok or type(decoded) ~= 'table' then
        local msg = ('failed to parse checks for %s #%s'):format(f.labels.pr_one, pr.num)
        render(buf, render_placeholder(msg, 'ForgeFail'))
        log.error(msg)
        return
      end
      local checks = normalize_checks(decoded, pr.scope, opts.job_filter)
      if #checks == 0 then
        local msg = opts.job_filter
            and ('No jobs matching "%s" for #%s'):format(opts.job_filter, pr.num)
          or ('No checks for #%s'):format(pr.num)
        render(buf, render_placeholder(msg, 'ForgeDim'))
        return
      end
      render(buf, render_rows(checks))
    end)
  end)
  set_data(buf, { proc = proc })
end

return M
