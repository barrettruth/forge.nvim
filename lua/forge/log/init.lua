local M = {}

local buf_lifecycle = require('forge.buf_lifecycle')
local config_mod = require('forge.config')
local log_render = require('forge.log.render')
local log_summary = require('forge.log.summary')
local scope_mod = require('forge.scope')
local ns = vim.api.nvim_create_namespace('forge_log')
local buf_data = {}

---@param opts forge.LogOpts
---@return string?
local function log_bufname(opts)
  local prefix = scope_mod.bufpath(opts.scope)
  if not prefix or not opts.run_id or opts.run_id == '' then
    return nil
  end
  if opts.job_id and opts.job_id ~= '' then
    return ('forge://%s/ci/run/%s/job/%s'):format(prefix, opts.run_id, opts.job_id)
  end
  return ('forge://%s/ci/run/%s/log'):format(prefix, opts.run_id)
end

---@param opts forge.SummaryOpts
---@return string?
local function summary_bufname(opts)
  local prefix = scope_mod.bufpath(opts.scope)
  if not prefix or not opts.run_id or opts.run_id == '' then
    return nil
  end
  return ('forge://%s/ci/run/%s'):format(prefix, opts.run_id)
end

local function new_data()
  return { headers = {}, errors = {} }
end

local find_buf_by_name = buf_lifecycle.find_buf_by_name
local set_public_buffer_state = buf_lifecycle.set_public_buffer_state

local function data_for(buf)
  return buf_lifecycle.data_for(buf_data, buf, new_data)
end

local function set_data(buf, fields)
  return buf_lifecycle.set_data(buf_data, buf, fields, new_data)
end

local function stop_procs(buf)
  buf_lifecycle.stop_procs(buf_data, buf, 'procs', new_data)
end

local function begin_request(buf)
  return buf_lifecycle.begin_request(buf_data, buf, stop_procs, new_data)
end

local function request_current(buf, request_id)
  return buf_lifecycle.request_current(buf_data, buf, request_id)
end

local strip_ansi = log_render.strip_ansi
local duration_label = log_render.duration_label
local parse_github = log_render.parse_github
local parse_gitlab = log_render.parse_gitlab
local parser_for = log_render.parser_for
local fold_meta = log_render.fold_meta

local function jump(buf, kind, dir)
  local d = buf_data[buf]
  if not d then
    return
  end
  local list = kind == 'header' and d.headers or d.errors
  buf_lifecycle.jump_positions(list, dir, false)
end

local function setup_keymaps(buf, url, cmd, opts)
  local cfg = config_mod.config()
  if cfg.keys == false then
    return
  end
  local keys = cfg.keys.log or {}
  local function map(key, fn, desc)
    if key and key ~= false then
      vim.keymap.set('n', key, fn, { buffer = buf, desc = desc })
    end
  end
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf, desc = 'Close log' })
  map(keys.next_step, function()
    jump(buf, 'header', 1)
  end, 'Next step')
  map(keys.prev_step, function()
    jump(buf, 'header', -1)
  end, 'Previous step')
  vim.keymap.set('n', ']d', function()
    jump(buf, 'error', 1)
  end, { buffer = buf, desc = 'Next error' })
  vim.keymap.set('n', '[d', function()
    jump(buf, 'error', -1)
  end, { buffer = buf, desc = 'Previous error' })
  vim.keymap.set('n', 'gx', function()
    if url then
      vim.ui.open(url)
    end
  end, { buffer = buf, desc = 'Browse' })
  map(keys.refresh, function()
    M.open(cmd, opts, buf)
  end, 'Refresh')
end

function M._foldtext()
  local lnum = vim.v.foldstart
  local buf = vim.api.nvim_get_current_buf()
  local d = buf_data[buf]
  local line = vim.fn.getline(lnum)
  if not d or not d.fold_meta then
    return line
  end
  local meta = d.fold_meta[lnum]
  if not meta or not meta.duration then
    return line
  end
  local hl = meta.conclusion == 'failure' and 'ForgeFail' or 'ForgeLogStep'
  local dur = duration_label(meta.duration)
  local width = vim.api.nvim_win_get_width(0)
  local pad = math.max(1, width - vim.fn.strdisplaywidth(line) - #dur - 1)
  return {
    { line, hl },
    { (' '):rep(pad), '' },
    { dur, 'ForgeLogDim' },
  }
end

---@class forge.LogOpts
---@field forge_name string
---@field scope forge.Scope?
---@field run_id string?
---@field url string?
---@field steps_cmd string[]?
---@field job_id string?
---@field replace_win integer?
---@field in_progress boolean?
---@field status_cmd string[]?

local function stop_timer(buf)
  local d = buf_data[buf]
  if d and d.timer then
    d.timer:stop()
    if not d.timer:is_closing() then
      d.timer:close()
    end
    d.timer = nil
  end
end

local function start_auto_refresh(buf, request_id, interval, status_cmd, refresh_fn)
  if interval <= 0 then
    return
  end
  stop_timer(buf)
  local timer = vim.uv.new_timer()
  data_for(buf).timer = timer
  timer:start(
    interval * 1000,
    interval * 1000,
    vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        stop_timer(buf)
        return
      end
      if not request_current(buf, request_id) then
        stop_timer(buf)
        return
      end
      if status_cmd then
        vim.system(status_cmd, { text = true }, function(result)
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(buf) then
              stop_timer(buf)
              return
            end
            if not request_current(buf, request_id) then
              stop_timer(buf)
              return
            end
            local ok, data = pcall(vim.json.decode, result.stdout or '{}')
            local completed = ok and data and data.status == 'completed'
            refresh_fn(completed)
            if completed then
              stop_timer(buf)
            end
          end)
        end)
      else
        refresh_fn(false)
      end
    end)
  )
end

---@param cmd string[]
---@param opts forge.LogOpts
---@param reuse_buf integer?
function M.open(cmd, opts, reuse_buf)
  local parse = parser_for[opts.forge_name] or parse_github
  local bufname = log_bufname(opts)
  local buf
  local saved_cursor
  local old_line_count
  local reusing = false
  if reuse_buf and vim.api.nvim_buf_is_valid(reuse_buf) then
    reusing = true
    buf = reuse_buf
    old_line_count = vim.api.nvim_buf_line_count(buf)
    local wins = vim.fn.win_findbuf(buf)
    if #wins > 0 then
      saved_cursor = vim.api.nvim_win_get_cursor(wins[1])
    end
  else
    local existing = find_buf_by_name(bufname)
    if existing then
      reusing = true
      buf = existing
      old_line_count = vim.api.nvim_buf_line_count(buf)
      local wins = vim.fn.win_findbuf(buf)
      if #wins > 0 then
        saved_cursor = vim.api.nvim_win_get_cursor(wins[1])
      else
        vim.cmd('noautocmd botright sbuffer ' .. buf)
      end
    else
      local replace_win = opts.replace_win
      if replace_win and vim.api.nvim_win_is_valid(replace_win) then
        local old_buf = vim.api.nvim_win_get_buf(replace_win)
        buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_win_set_buf(replace_win, buf)
        if vim.api.nvim_buf_is_valid(old_buf) and old_buf ~= buf then
          vim.api.nvim_buf_delete(old_buf, { force = true })
        end
      else
        vim.cmd('noautocmd botright new')
        buf = vim.api.nvim_get_current_buf()
      end
      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.bo[buf].swapfile = false
      vim.bo[buf].modifiable = false
      if bufname then
        vim.api.nvim_buf_set_name(buf, bufname)
      end
      setup_keymaps(buf, opts.url, cmd, opts)
      vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = buf,
        callback = function()
          stop_timer(buf)
          stop_procs(buf)
          buf_data[buf] = nil
        end,
      })
    end
  end
  vim.bo[buf].filetype = 'forgelog'
  set_public_buffer_state(buf, 'ci_log', opts.url)
  if not reusing then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Loading...' })
    vim.bo[buf].modifiable = false
  end
  local request_id = begin_request(buf)

  local log_result, steps
  local pending = opts.steps_cmd and 2 or 1

  local function try_render()
    pending = pending - 1
    if pending > 0 then
      return
    end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      if not request_current(buf, request_id) then
        return
      end
      local stdout = (log_result.stdout or '')
      if log_result.code ~= 0 or stdout == '' then
        local msg = vim.trim(log_result.stderr or stdout)
        if msg == '' then
          msg = 'no log output'
        end
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(msg, '\n'))
        vim.bo[buf].modifiable = false
        set_data(buf, { headers = {}, errors = {}, fold_meta = {} })
        return
      end
      local raw_lines = vim.split(stdout, '\n', { plain = true })
      if raw_lines[#raw_lines] == '' then
        raw_lines[#raw_lines] = nil
      end
      local parsed = parse(raw_lines, steps)
      set_data(buf, {
        headers = parsed.headers,
        errors = parsed.errors,
        fold_meta = fold_meta(parsed),
      })
      log_render.render(buf, ns, parsed)
      local wins = vim.fn.win_findbuf(buf)
      if #wins > 0 then
        local win = wins[1]
        local lc = vim.api.nvim_buf_line_count(buf)
        if saved_cursor then
          local was_at_bottom = old_line_count and saved_cursor[1] >= old_line_count
          if was_at_bottom then
            vim.api.nvim_win_set_cursor(win, { lc, 0 })
          else
            saved_cursor[1] = math.min(saved_cursor[1], lc)
            vim.api.nvim_win_set_cursor(win, saved_cursor)
          end
        else
          vim.api.nvim_win_set_cursor(win, { lc, 0 })
        end
      end

      if opts.in_progress then
        local cfg = config_mod.config()
        start_auto_refresh(buf, request_id, cfg.ci.refresh, opts.status_cmd, function(completed)
          if completed then
            opts = vim.tbl_extend('force', opts, { in_progress = false })
          end
          M.open(cmd, opts, buf)
        end)
      end
    end)
  end

  local procs = {}
  procs[#procs + 1] = vim.system(cmd, { text = true }, function(result)
    log_result = result
    try_render()
  end)

  if opts.steps_cmd then
    procs[#procs + 1] = vim.system(opts.steps_cmd, { text = true }, function(result)
      if result.code == 0 and result.stdout and result.stdout ~= '' then
        local ok, data = pcall(vim.json.decode, result.stdout)
        if ok and data and data.jobs then
          local job_id = opts.job_id and tonumber(opts.job_id)
          for _, j in ipairs(data.jobs) do
            if not job_id or j.databaseId == job_id then
              steps = j.steps
              break
            end
          end
        end
      end
      try_render()
    end)
  end
  set_data(buf, { procs = procs })
end

---@class forge.SummaryOpts
---@field forge_name string
---@field scope forge.Scope?
---@field run_id string
---@field url string?
---@field in_progress boolean?
---@field status_cmd string[]?
---@field json boolean?
---@field job_filter string?
---@field browse_url_fn fun(job_id: string): string?
---@field log_cmd_fn fun(job_id: string, failed: boolean): string[], forge.LogOpts

local normalize_job_filter_input = log_summary.normalize_job_filter_input
local filter_summary = log_summary.filter_summary
local parse_summary = log_summary.parse_summary
local summary_job_at_line = log_summary.summary_job_at_line
local parse_summary_json = log_summary.parse_summary_json

---@param cmd string[]
---@param opts forge.SummaryOpts
---@param reuse_buf integer?
function M.open_summary(cmd, opts, reuse_buf)
  local bufname = summary_bufname(opts)
  local buf
  local saved_cursor
  local old_line_count
  local reusing = false
  if reuse_buf and vim.api.nvim_buf_is_valid(reuse_buf) then
    reusing = true
    buf = reuse_buf
    old_line_count = vim.api.nvim_buf_line_count(buf)
    local wins = vim.fn.win_findbuf(buf)
    if #wins > 0 then
      saved_cursor = vim.api.nvim_win_get_cursor(wins[1])
    end
  else
    local existing = find_buf_by_name(bufname)
    if existing then
      reusing = true
      buf = existing
      old_line_count = vim.api.nvim_buf_line_count(buf)
      local wins = vim.fn.win_findbuf(buf)
      if #wins > 0 then
        saved_cursor = vim.api.nvim_win_get_cursor(wins[1])
      else
        local cfg = config_mod.config()
        local split = cfg.ci.split or cfg.split
        local prefix = split == 'vertical' and 'vertical' or 'botright'
        vim.cmd('noautocmd ' .. prefix .. ' sbuffer ' .. buf)
      end
    else
      local cfg = config_mod.config()
      local split = cfg.ci.split or cfg.split
      local prefix = split == 'vertical' and 'vertical' or 'botright'
      vim.cmd('noautocmd ' .. prefix .. ' new')
      buf = vim.api.nvim_get_current_buf()
      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.bo[buf].swapfile = false
      vim.bo[buf].modifiable = false
      if bufname then
        vim.api.nvim_buf_set_name(buf, bufname)
      end
      vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = buf,
        callback = function()
          stop_timer(buf)
          stop_procs(buf)
          buf_data[buf] = nil
        end,
      })
    end
  end
  vim.bo[buf].filetype = 'forgelist'
  set_public_buffer_state(buf, 'ci_summary', opts.url)

  if not reusing then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Loading...' })
    vim.bo[buf].modifiable = false
  end
  local request_id = begin_request(buf)

  local proc = vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      if not request_current(buf, request_id) then
        return
      end
      local stdout = result.stdout or ''
      if result.code ~= 0 or stdout == '' then
        local msg = vim.trim(result.stderr or stdout)
        if msg == '' then
          msg = 'no output'
        end
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(msg, '\n'))
        vim.bo[buf].modifiable = false
        set_data(buf, { headers = {}, errors = {}, jobs = nil })
        return
      end

      local parsed
      if opts.json then
        local ok, data = pcall(vim.json.decode, stdout)
        if ok and data then
          parsed = parse_summary_json(data)
        end
      end
      if not parsed then
        local raw_lines = vim.split(stdout, '\n', { plain = true })
        if raw_lines[#raw_lines] == '' then
          raw_lines[#raw_lines] = nil
        end
        parsed = parse_summary(raw_lines)
      end
      parsed = filter_summary(parsed, opts.job_filter)

      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, parsed.lines)
      vim.bo[buf].modifiable = false

      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      for i, h in ipairs(parsed.hls) do
        for _, hl in ipairs(h) do
          vim.api.nvim_buf_set_extmark(buf, ns, i - 1, hl.col, {
            end_col = hl.end_col,
            hl_group = hl.group,
          })
        end
      end

      set_data(buf, {
        headers = parsed.job_lnums,
        errors = {},
        jobs = parsed.jobs,
      })

      if not reusing then
        local cfg = config_mod.config()
        if cfg.keys ~= false then
          local keys = cfg.keys.log or {}
          local function map(key, fn, desc)
            if key and key ~= false then
              vim.keymap.set('n', key, fn, { buffer = buf, desc = desc })
            end
          end
          vim.keymap.set('n', 'q', function()
            vim.api.nvim_buf_delete(buf, { force = true })
          end, { buffer = buf, desc = 'Close' })
          vim.keymap.set('n', 'gx', function()
            local url = opts.url
            local d = buf_data[buf]
            if d and d.jobs then
              local job = d.jobs[vim.api.nvim_win_get_cursor(0)[1]]
              if job and opts.browse_url_fn then
                url = opts.browse_url_fn(job.id) or url
              end
            end
            if url then
              vim.ui.open(url)
            end
          end, { buffer = buf, desc = 'Browse' })
          map(keys.refresh, function()
            M.open_summary(cmd, opts, buf)
          end, 'Refresh')
          map(keys.filter, function()
            vim.ui.input(
              { prompt = 'Filter jobs: ', default = opts.job_filter or '' },
              function(input)
                local next_filter, cancelled = normalize_job_filter_input(input)
                if cancelled then
                  return
                end
                vim.schedule(function()
                  if not vim.api.nvim_buf_is_valid(buf) then
                    return
                  end
                  opts.job_filter = next_filter
                  M.open_summary(cmd, opts, buf)
                end)
              end
            )
          end, 'Filter jobs')
          map(keys.next_step, function()
            jump(buf, 'header', 1)
          end, 'Next job')
          map(keys.prev_step, function()
            jump(buf, 'header', -1)
          end, 'Previous job')
          vim.keymap.set('n', '<cr>', function()
            local lnum = vim.api.nvim_win_get_cursor(0)[1]
            local d = buf_data[buf]
            if not d or not d.jobs then
              return
            end
            local job = d.jobs[lnum]
            if job and opts.log_cmd_fn then
              local log_cmd, log_opts = opts.log_cmd_fn(job.id, job.failed)
              log_opts = vim.tbl_extend('force', log_opts, {
                replace_win = vim.api.nvim_get_current_win(),
              })
              M.open(log_cmd, log_opts)
            end
          end, { buffer = buf, desc = 'Open job log' })
        end
      end

      local wins = vim.fn.win_findbuf(buf)
      if #wins > 0 then
        local win = wins[1]
        if saved_cursor then
          local lc = vim.api.nvim_buf_line_count(buf)
          local was_at_bottom = old_line_count and saved_cursor[1] >= old_line_count
          if was_at_bottom then
            vim.api.nvim_win_set_cursor(win, { lc, 0 })
          else
            saved_cursor[1] = math.min(saved_cursor[1], lc)
            vim.api.nvim_win_set_cursor(win, saved_cursor)
          end
        end
      end

      if opts.in_progress then
        local cfg = config_mod.config()
        start_auto_refresh(buf, request_id, cfg.ci.refresh, opts.status_cmd, function(completed)
          if completed then
            opts = vim.tbl_extend('force', opts, { in_progress = false })
          end
          M.open_summary(cmd, opts, buf)
        end)
      end
    end)
  end)

  set_data(buf, { procs = { proc } })
end

M._strip_ansi = strip_ansi
M._parse_github = parse_github
M._parse_gitlab = parse_gitlab
M._parse_summary = parse_summary
M._summary_job_at_line = summary_job_at_line
M._parse_summary_json = parse_summary_json

return M
