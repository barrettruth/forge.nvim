local M = {}

local buf_lifecycle = require('forge.buf_lifecycle')
local config_mod = require('forge.config')
local format_mod = require('forge.format')
local layout = require('forge.format.layout')
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
  return buf_lifecycle.data_for(buf_data, buf)
end

local function set_data(buf, fields)
  return buf_lifecycle.set_data(buf_data, buf, fields)
end

local function stop_proc(buf)
  buf_lifecycle.stop_proc(buf_data, buf)
end

local function begin_request(buf)
  return buf_lifecycle.begin_request(buf_data, buf, stop_proc)
end

local function request_current(buf, request_id)
  return buf_lifecycle.request_current(buf_data, buf, request_id)
end

local function jump(buf, dir)
  local positions = buf_lifecycle.line_positions(data_for(buf).lines, 'check')
  buf_lifecycle.jump_positions(positions, dir, true)
end

---@param buf integer
---@return forge.Check?
local function current_check(buf)
  return buf_lifecycle.current_line_value(data_for(buf).lines, 'check')
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
  local rows = format_mod.format_checks(display_checks, { width = layout.picker_width() })
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
  buf_lifecycle.render_simple(buf, ns, lines)
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
  local cfg = config_mod.config()
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
  local cfg = config_mod.config()
  local split = cfg.ci.split or cfg.split
  local buf, reusing = buf_lifecycle.prepare_buf({
    bufname = bufname(pr),
    reuse_buf = reuse_buf,
    split = split,
    filetype = 'forgelist',
    kind = 'pr_checks',
    url = scope_mod.subject_web_url('pr', pr.num, pr.scope),
    on_wipeout = function(wiped)
      stop_proc(wiped)
      buf_data[wiped] = nil
    end,
  })
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
  local normalized = vim.deepcopy(checks)
  for _, check in ipairs(normalized) do
    check.scope = check.scope or scope
  end
  local filtered = format_mod.filter_checks(normalized, 'all')
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
