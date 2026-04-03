local M = {}

local ns = vim.api.nvim_create_namespace('forge_log')
local buf_data = {}

local sgr_map = {
  [2] = 'ForgeLogDim',
  [31] = 'ForgeFail',
  [32] = 'ForgePass',
  [33] = 'ForgeLogWarning',
  [34] = 'ForgeLogStep',
  [36] = 'ForgeLogSection',
  [91] = 'ForgeFail',
  [92] = 'ForgePass',
  [93] = 'ForgeLogWarning',
  [96] = 'ForgeLogSection',
}

local function strip_ansi(line)
  if line:byte(1) == 0xEF and line:byte(2) == 0xBB and line:byte(3) == 0xBF then
    line = line:sub(4)
  end
  line = line:gsub('\r', '')
  local parts = {}
  local hls = {}
  local pos = 1
  local col = 0
  local grp, grp_start
  while pos <= #line do
    local es, ee, params, code = line:find('\027%[([%d;]*)([A-Za-z])', pos)
    if not es then
      local chunk = line:sub(pos)
      parts[#parts + 1] = chunk
      col = col + #chunk
      break
    end
    if es > pos then
      local chunk = line:sub(pos, es - 1)
      parts[#parts + 1] = chunk
      col = col + #chunk
    end
    if code == 'm' then
      if grp and col > grp_start then
        hls[#hls + 1] = { col = grp_start, end_col = col, group = grp }
      end
      grp = nil
      if params ~= '' and params ~= '0' then
        for p in params:gmatch('(%d+)') do
          local n = tonumber(p)
          if n == 0 then
            grp = nil
          elseif sgr_map[n] then
            grp = sgr_map[n]
            grp_start = col
          end
        end
      end
    end
    pos = ee + 1
  end
  if grp and col > grp_start then
    hls[#hls + 1] = { col = grp_start, end_col = col, group = grp }
  end
  return table.concat(parts), hls
end

local function offset_hls(hls, n)
  for i, hl in ipairs(hls) do
    hls[i] = { col = hl.col + n, end_col = hl.end_col + n, group = hl.group }
  end
  return hls
end

---@type table<string, string>
local step_icons = {
  success = '✓',
  failure = '✗',
  skipped = '⊘',
}

---@param started string?
---@param completed string?
---@return string?
local function format_duration(started, completed)
  if not started or not completed then
    return nil
  end
  local function parse_iso(s)
    local y, mo, d, h, mi, sec = s:match('^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
    if not y then
      return nil
    end
    return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = sec })
  end
  local t0 = parse_iso(started)
  local t1 = parse_iso(completed)
  if not t0 or not t1 then
    return nil
  end
  local diff = math.max(0, t1 - t0)
  if diff < 60 then
    return ('%ds'):format(diff)
  elseif diff < 3600 then
    return ('%dm %ds'):format(math.floor(diff / 60), diff % 60)
  end
  return ('%dh %dm'):format(math.floor(diff / 3600), math.floor(diff % 3600 / 60))
end

---@class forge.StepEntry
---@field name string
---@field conclusion string
---@field started string?
---@field completed string?
---@field number integer
---@field emitted boolean

---@class forge.StepLookup
---@field by_name table<string, forge.StepEntry>
---@field ordered forge.StepEntry[]
---@field post_steps forge.StepEntry[]
---@field setup forge.StepEntry?
---@field complete forge.StepEntry?

---@param steps table[]?
---@return forge.StepLookup?
local function build_step_lookup(steps)
  if not steps or #steps == 0 then
    return nil
  end
  table.sort(steps, function(a, b)
    return a.number < b.number
  end)
  local lookup = {
    by_name = {},
    ordered = {},
    post_steps = {},
  }
  for _, s in ipairs(steps) do
    local entry = {
      name = s.name,
      conclusion = s.conclusion or '',
      started = s.startedAt,
      completed = s.completedAt,
      number = s.number,
      emitted = false,
    }
    lookup.ordered[#lookup.ordered + 1] = entry
    lookup.by_name[s.name] = entry
    if s.name == 'Set up job' then
      lookup.setup = entry
    elseif s.name == 'Complete job' then
      lookup.complete = entry
    elseif s.name:match('^Post ') then
      lookup.post_steps[#lookup.post_steps + 1] = entry
    end
  end
  return #lookup.ordered > 0 and lookup or nil
end

---@param raw_lines string[]
---@param steps table[]?
---@return { lines: table[], headers: integer[], errors: integer[] }
local function parse_github(raw_lines, steps)
  local lines = {}
  local headers = {}
  local errors = {}
  local cur_job, cur_step
  local in_group = false
  local lookup = build_step_lookup(steps)
  local post_idx = 0
  local unknown_step = false

  ---@param se forge.StepEntry
  local function emit_step(se)
    if se.emitted then
      return
    end
    se.emitted = true
    in_group = false
    local icon = step_icons[se.conclusion] or '●'
    local dur = format_duration(se.started, se.completed)
    lines[#lines + 1] = {
      text = ('%s %s'):format(icon, se.name),
      hls = {},
      fold = '>2',
      kind = 'step',
      duration = dur,
      conclusion = se.conclusion,
    }
    headers[#headers + 1] = #lines
  end

  for _, raw in ipairs(raw_lines) do
    if raw:byte(1) == 0xEF and raw:byte(2) == 0xBB and raw:byte(3) == 0xBF then
      raw = raw:sub(4)
    end
    raw = raw:gsub('\r', '')
    local job, step, rest = raw:match('^([^\t]*)\t([^\t]*)\t(.*)$')
    if not job then
      local text, h = strip_ansi(raw)
      lines[#lines + 1] = { text = text, hls = h, fold = '0', kind = 'raw' }
      goto continue
    end
    if job ~= cur_job then
      cur_job = job
      cur_step = nil
      post_idx = 0
      in_group = false
      lines[#lines + 1] = { text = job, hls = {}, fold = '>1', kind = 'job' }
      headers[#headers + 1] = #lines
      if lookup and lookup.setup then
        emit_step(lookup.setup)
      end
    end
    if not lookup and step ~= cur_step then
      cur_step = step
      in_group = false
      unknown_step = step == 'UNKNOWN STEP'
      if not unknown_step then
        lines[#lines + 1] = { text = '  ' .. step, hls = {}, fold = '>2', kind = 'step' }
        headers[#headers + 1] = #lines
      end
    end
    do
      local _, content = rest:match('^(%d%d%d%d%-%d%d%-%d%dT[%d:.]+Z)%s(.*)$')
      if not content then
        content = rest
      end

      if lookup then
        if content == 'Post job cleanup.' then
          post_idx = post_idx + 1
          if lookup.post_steps[post_idx] then
            emit_step(lookup.post_steps[post_idx])
          end
        elseif content:match('^Cleaning up orphan processes') then
          if lookup.complete then
            emit_step(lookup.complete)
          end
        end
      end

      local kind, m = 'content', nil
      m = content:match('^##%[error[^%]]*%](.*)$')
      if m then
        kind = 'error'
        content = 'Error: ' .. m
        goto emit
      end
      m = content:match('^##%[warning[^%]]*%](.*)$')
      if m then
        kind = 'warning'
        content = 'Warning: ' .. m
        goto emit
      end
      m = content:match('^##%[group%](.*)$')
      if m then
        if lookup and lookup.by_name[m] then
          emit_step(lookup.by_name[m])
        end
        kind = 'group'
        content = m
        goto emit
      end
      if content:match('^##%[endgroup') then
        in_group = false
        goto continue
      end
      m = content:match('^##%[debug[^%]]*%](.*)$')
      if m then
        kind = 'debug'
        content = m
        goto emit
      end
      m = content:match('^##%[notice[^%]]*%](.*)$')
      if m then
        kind = 'notice'
        content = m
        goto emit
      end
      m = content:match('^%[command%](.*)$')
      if m then
        kind = 'command'
        content = m
      end
      ::emit::
      local text, h = strip_ansi(content)
      if kind == 'error' or kind == 'warning' then
        h = {}
      end
      local indent_n
      local fold_val
      if lookup then
        if kind == 'group' then
          indent_n = 2
          fold_val = '>3'
        elseif in_group then
          indent_n = 4
          fold_val = '3'
        else
          indent_n = 2
          fold_val = '2'
        end
      else
        indent_n = (unknown_step and not in_group) and 2 or 4
        if kind == 'group' then
          fold_val = unknown_step and '>2' or '>3'
        elseif unknown_step then
          fold_val = in_group and '2' or '1'
        elseif in_group then
          fold_val = '3'
        else
          fold_val = '2'
        end
      end
      lines[#lines + 1] = {
        text = (' '):rep(indent_n) .. text,
        hls = offset_hls(h, indent_n),
        fold = fold_val,
        kind = kind,
      }
      if kind == 'error' then
        errors[#errors + 1] = #lines
      elseif kind == 'group' then
        headers[#headers + 1] = #lines
        in_group = true
      end
    end
    ::continue::
  end
  if lookup then
    for _, se in ipairs(lookup.ordered) do
      emit_step(se)
    end
  end
  return { lines = lines, headers = headers, errors = errors }
end

local function parse_gitlab(raw_lines)
  local lines = {}
  local headers = {}
  local errors = {}
  local in_section = false

  local function process_section_start(raw)
    local _, sep_end = raw:find('\027%[0K')
    local header_raw
    if sep_end then
      header_raw = raw:sub(sep_end + 1)
    else
      header_raw = raw:match('^section_start:%d+:(.+)$') or ''
    end
    local text, h = strip_ansi(header_raw)
    if text == '' then
      text = raw:match('^section_start:%d+:([^%c\027]+)') or 'section'
    end
    lines[#lines + 1] = { text = text, hls = h, fold = '>1', kind = 'section' }
    headers[#headers + 1] = #lines
    in_section = true
  end

  local function process_content(raw)
    local text, h = strip_ansi(raw)
    if text == '' then
      return
    end
    local prefix = in_section and '  ' or ''
    if #prefix > 0 then
      offset_hls(h, #prefix)
    end
    local kind = 'content'
    for _, hl in ipairs(h) do
      if hl.group == 'ForgeFail' then
        kind = 'error'
        break
      end
    end
    lines[#lines + 1] = {
      text = prefix .. text,
      hls = h,
      fold = in_section and '1' or '0',
      kind = kind,
    }
    if kind == 'error' then
      errors[#errors + 1] = #lines
    end
  end

  for _, raw in ipairs(raw_lines) do
    raw = raw:gsub('\r', '')
    if raw:match('^section_start:') then
      process_section_start(raw)
    elseif raw:match('^section_end:') then
      in_section = false
      local _, sep_end = raw:find('\027%[0K')
      local remainder = sep_end and raw:sub(sep_end + 1) or ''
      if remainder:match('^section_start:') then
        process_section_start(remainder)
      elseif remainder ~= '' then
        process_content(remainder)
      end
    else
      process_content(raw)
    end
  end
  return { lines = lines, headers = headers, errors = errors }
end

local parser_for = {
  github = parse_github,
  codeberg = parse_github,
  gitlab = parse_gitlab,
}

local function fold_ranges(parsed)
  local ranges = {}
  local stack = {}
  for i, line in ipairs(parsed.lines) do
    local expr = line.fold
    if expr:sub(1, 1) == '>' then
      local level = tonumber(expr:sub(2))
      while #stack > 0 and stack[#stack].level >= level do
        local f = table.remove(stack)
        if i - 1 > f.start then
          ranges[#ranges + 1] = { f.start, i - 1, f.level }
        end
      end
      stack[#stack + 1] = { start = i, level = level }
    else
      local level = tonumber(expr) or 0
      while #stack > 0 and stack[#stack].level > level do
        local f = table.remove(stack)
        if i - 1 > f.start then
          ranges[#ranges + 1] = { f.start, i - 1, f.level }
        end
      end
    end
  end
  local n = #parsed.lines
  while #stack > 0 do
    local f = table.remove(stack)
    if n > f.start then
      ranges[#ranges + 1] = { f.start, n, f.level }
    end
  end
  table.sort(ranges, function(a, b)
    return a[3] > b[3]
  end)
  return ranges
end

local function render(buf, parsed)
  local texts = {}
  for i, line in ipairs(parsed.lines) do
    texts[i] = line.text
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, texts)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, line in ipairs(parsed.lines) do
    local lnum = i - 1
    if line.kind == 'job' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogJob' })
    elseif line.kind == 'step' then
      local hl = line.conclusion == 'failure' and 'ForgeFail' or 'ForgeLogStep'
      local ext_opts = { line_hl_group = hl }
      if line.duration then
        ext_opts.virt_text = { { line.duration, 'ForgeLogDim' } }
        ext_opts.virt_text_pos = 'eol'
      end
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, ext_opts)
    elseif line.kind == 'group' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogStep' })
    elseif line.kind == 'section' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogSection' })
    elseif line.kind == 'error' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogError' })
      local start = line.text:find('Error: ', 1, true)
      if start then
        vim.api.nvim_buf_set_extmark(buf, ns, lnum, start - 1, {
          end_col = start + 6,
          hl_group = 'ForgeLogErrorLabel',
        })
      end
    elseif line.kind == 'warning' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogWarning' })
      local start = line.text:find('Warning: ', 1, true)
      if start then
        vim.api.nvim_buf_set_extmark(buf, ns, lnum, start - 1, {
          end_col = start + 8,
          hl_group = 'ForgeLogWarningLabel',
        })
      end
    elseif line.kind == 'notice' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogWarning' })
    elseif line.kind == 'command' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, {
        end_col = #line.text,
        hl_group = 'ForgeLogCommand',
      })
    elseif line.kind == 'debug' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogDim' })
    end
    for _, hl in ipairs(line.hls) do
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, hl.col, {
        end_col = hl.end_col,
        hl_group = hl.group,
      })
    end
  end
  local fold_meta = {}
  for i, line in ipairs(parsed.lines) do
    if line.kind == 'step' and line.duration then
      fold_meta[i] = { duration = line.duration, conclusion = line.conclusion }
    end
  end
  buf_data[buf] = {
    headers = parsed.headers,
    errors = parsed.errors,
    fold_meta = fold_meta,
  }
  local ranges = fold_ranges(parsed)
  local wins = vim.fn.win_findbuf(buf)
  if #wins > 0 then
    vim.api.nvim_win_call(wins[1], function()
      vim.wo[0].foldmethod = 'manual'
      vim.wo[0].foldtext = 'v:lua.require("forge.log")._foldtext()'
      pcall(vim.cmd, 'silent! normal! zE')
      for _, r in ipairs(ranges) do
        vim.cmd(r[1] .. ',' .. r[2] .. 'fold')
      end
      vim.wo[0].foldlevel = 1
    end)
  end
end

local function jump(buf, kind, dir)
  local d = buf_data[buf]
  if not d then
    return
  end
  local list = kind == 'header' and d.headers or d.errors
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  if dir > 0 then
    for _, ln in ipairs(list) do
      if ln > cursor then
        vim.api.nvim_win_set_cursor(0, { ln, 0 })
        return
      end
    end
  else
    for i = #list, 1, -1 do
      if list[i] < cursor then
        vim.api.nvim_win_set_cursor(0, { list[i], 0 })
        return
      end
    end
  end
end

local function setup_keymaps(buf, url, cmd, opts)
  local cfg = require('forge').config()
  if cfg.keys == false then
    return
  end
  local keys = cfg.keys.log or {}
  local function map(key, fn, desc)
    if key and key ~= false then
      vim.keymap.set('n', key, fn, { buffer = buf, desc = desc })
    end
  end
  map(keys.close, function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, 'Close log')
  map(keys.next_step, function()
    jump(buf, 'header', 1)
  end, 'Next step')
  map(keys.prev_step, function()
    jump(buf, 'header', -1)
  end, 'Previous step')
  map(keys.next_error, function()
    jump(buf, 'error', 1)
  end, 'Next error')
  map(keys.prev_error, function()
    jump(buf, 'error', -1)
  end, 'Previous error')
  map(keys.browse, function()
    if url then
      vim.ui.open(url)
    end
  end, 'Browse')
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
  local dur = meta.duration
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
---@field url string?
---@field title string?
---@field steps_cmd string[]?
---@field job_id string?
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

local function start_auto_refresh(buf, interval, status_cmd, refresh_fn)
  if interval <= 0 then
    return
  end
  stop_timer(buf)
  local timer = vim.uv.new_timer()
  buf_data[buf] = buf_data[buf] or {}
  buf_data[buf].timer = timer
  timer:start(
    interval * 1000,
    interval * 1000,
    vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(buf) then
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
  local buf
  local saved_cursor
  local old_line_count
  if reuse_buf and vim.api.nvim_buf_is_valid(reuse_buf) then
    buf = reuse_buf
    old_line_count = vim.api.nvim_buf_line_count(buf)
    local wins = vim.fn.win_findbuf(buf)
    if #wins > 0 then
      saved_cursor = vim.api.nvim_win_get_cursor(wins[1])
    end
  else
    vim.cmd('noautocmd botright new')
    buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = 'forge_log'
    pcall(vim.api.nvim_buf_set_name, buf, 'forge://log/' .. (opts.title or 'ci'))
    setup_keymaps(buf, opts.url, cmd, opts)
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      callback = function()
        stop_timer(buf)
        local d = buf_data[buf]
        if d and d.procs then
          for _, p in ipairs(d.procs) do
            pcall(function()
              p:kill()
            end)
          end
        end
        buf_data[buf] = nil
      end,
    })
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Loading...' })
  vim.bo[buf].modifiable = false

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
      local stdout = (log_result.stdout or '')
      if log_result.code ~= 0 or stdout == '' then
        local msg = vim.trim(log_result.stderr or stdout)
        if msg == '' then
          msg = 'no log output'
        end
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(msg, '\n'))
        vim.bo[buf].modifiable = false
        buf_data[buf] = { headers = {}, errors = {} }
        return
      end
      local raw_lines = vim.split(stdout, '\n', { plain = true })
      if raw_lines[#raw_lines] == '' then
        raw_lines[#raw_lines] = nil
      end
      local parsed = parse(raw_lines, steps)
      render(buf, parsed)
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
        local cfg = require('forge').config()
        start_auto_refresh(buf, cfg.ci.refresh, opts.status_cmd, function(completed)
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
  buf_data[buf] = buf_data[buf] or {}
  buf_data[buf].procs = procs
end

---@class forge.SummaryOpts
---@field forge_name string
---@field run_id string
---@field url string?
---@field title string?
---@field in_progress boolean?
---@field status_cmd string[]?
---@field log_cmd_fn fun(job_id: string, failed: boolean): string[], forge.LogOpts

local function parse_summary(raw_lines)
  local lines = {}
  local hls = {}
  local jobs = {}
  local job_lnums = {}

  for _, raw in ipairs(raw_lines) do
    local text, h = strip_ansi(raw)
    lines[#lines + 1] = text
    hls[#hls + 1] = h
    local job_id = text:match('%(ID (%d+)%)%s*$')
    if job_id then
      local failed = text:match('^X ') ~= nil
      jobs[#lines] = { id = job_id, failed = failed }
      job_lnums[#job_lnums + 1] = #lines
    end
  end

  return { lines = lines, hls = hls, jobs = jobs, job_lnums = job_lnums }
end

---@param cmd string[]
---@param opts forge.SummaryOpts
---@param reuse_buf integer?
function M.open_summary(cmd, opts, reuse_buf)
  local buf
  local saved_cursor
  local old_line_count
  if reuse_buf and vim.api.nvim_buf_is_valid(reuse_buf) then
    buf = reuse_buf
    old_line_count = vim.api.nvim_buf_line_count(buf)
    local wins = vim.fn.win_findbuf(buf)
    if #wins > 0 then
      saved_cursor = vim.api.nvim_win_get_cursor(wins[1])
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
    vim.bo[buf].filetype = 'forge_log'
    pcall(vim.api.nvim_buf_set_name, buf, 'forge://ci/' .. (opts.title or 'summary'))
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      callback = function()
        stop_timer(buf)
        local d = buf_data[buf]
        if d and d.procs then
          for _, p in ipairs(d.procs) do
            pcall(function()
              p:kill()
            end)
          end
        end
        buf_data[buf] = nil
      end,
    })
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Loading...' })
  vim.bo[buf].modifiable = false

  local proc = vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
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
        buf_data[buf] = { headers = {}, errors = {} }
        return
      end

      local raw_lines = vim.split(stdout, '\n', { plain = true })
      if raw_lines[#raw_lines] == '' then
        raw_lines[#raw_lines] = nil
      end
      local parsed = parse_summary(raw_lines)

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

      buf_data[buf] = {
        headers = parsed.job_lnums,
        errors = {},
        jobs = parsed.jobs,
      }

      if not reuse_buf then
        local cfg = require('forge').config()
        if cfg.keys ~= false then
          local keys = cfg.keys.log or {}
          local function map(key, fn, desc)
            if key and key ~= false then
              vim.keymap.set('n', key, fn, { buffer = buf, desc = desc })
            end
          end
          map(keys.close, function()
            vim.api.nvim_buf_delete(buf, { force = true })
          end, 'Close')
          map(keys.browse, function()
            if opts.url then
              vim.ui.open(opts.url)
            end
          end, 'Browse')
          map(keys.refresh, function()
            M.open_summary(cmd, opts, buf)
          end, 'Refresh')
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
            if not job then
              for i = lnum, 1, -1 do
                if d.jobs[i] then
                  job = d.jobs[i]
                  break
                end
              end
            end
            if job and opts.log_cmd_fn then
              local log_cmd, log_opts = opts.log_cmd_fn(job.id, job.failed)
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
        local cfg = require('forge').config()
        start_auto_refresh(buf, cfg.ci.refresh, opts.status_cmd, function(completed)
          if completed then
            opts = vim.tbl_extend('force', opts, { in_progress = false })
          end
          M.open_summary(cmd, opts, buf)
        end)
      end
    end)
  end)

  buf_data[buf] = buf_data[buf] or {}
  buf_data[buf].procs = { proc }
end

M._strip_ansi = strip_ansi
M._parse_github = parse_github
M._parse_gitlab = parse_gitlab

return M
