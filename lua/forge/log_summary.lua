local M = {}

local log_render = require('forge.log_render')

local strip_ansi = log_render.strip_ansi
local summary_status = log_render.summary_status
local summary_status_group = log_render.summary_status_group
local summary_status_icon = log_render.summary_status_icon
local duration_label = log_render.duration_label
local format_duration = log_render.format_duration

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
  local candidate = type(name) == 'string' and strip_ansi(name):lower() or ''
  return candidate:find(job_filter:lower(), 1, true) ~= nil
end

local function filter_summary(parsed, job_filter)
  if type(job_filter) ~= 'string' or job_filter == '' then
    return parsed
  end
  local matched_ids = {}
  local header_rows = {}
  for _, lnum in ipairs(parsed.job_lnums or {}) do
    header_rows[lnum] = true
    local job = parsed.jobs and parsed.jobs[lnum] or nil
    if job and job.id and matches_job_filter(parsed.lines[lnum], job_filter) then
      matched_ids[job.id] = true
    end
  end
  local lines = {}
  local hls = {}
  local jobs = {}
  local job_lnums = {}
  local first_job = parsed.job_lnums and parsed.job_lnums[1] or nil
  local header_limit = first_job and (first_job - 1) or 0
  for lnum = 1, header_limit do
    lines[#lines + 1] = parsed.lines[lnum]
    hls[#lines] = parsed.hls[lnum] or {}
  end
  if next(matched_ids) == nil then
    local text = ('No jobs matching "%s"'):format(job_filter)
    lines[#lines + 1] = text
    hls[#lines] = {
      {
        col = 0,
        end_col = #text,
        group = 'ForgeDim',
      },
    }
    return { lines = lines, hls = hls, jobs = jobs, job_lnums = job_lnums }
  end
  for lnum, line in ipairs(parsed.lines or {}) do
    local job = parsed.jobs and parsed.jobs[lnum] or nil
    if job and matched_ids[job.id] then
      lines[#lines + 1] = line
      hls[#lines] = parsed.hls[lnum] or {}
      jobs[#lines] = job
      if header_rows[lnum] then
        job_lnums[#job_lnums + 1] = #lines
      end
    end
  end
  return { lines = lines, hls = hls, jobs = jobs, job_lnums = job_lnums }
end

local function parse_summary(raw_lines)
  local lines = {}
  local hls = {}
  local jobs = {}
  local job_lnums = {}
  local section
  local current_job
  local first = 1
  local last = #raw_lines

  while first <= last do
    local text = strip_ansi(raw_lines[first])
    if not text:match('^%s*$') then
      break
    end
    first = first + 1
  end

  while last >= first do
    local text = strip_ansi(raw_lines[last])
    if not text:match('^%s*$') then
      break
    end
    last = last - 1
  end

  for i = first, last do
    local raw = raw_lines[i]
    local text, h = strip_ansi(raw)
    local lnum = #lines + 1
    if text:match('^%s*$') then
      text = ''
      h = {}
      current_job = nil
    else
      local prefix = text:match('^(%S+)')
      local status = prefix and summary_status(prefix) or nil
      if text:match('^%u[%u%s]+$') then
        section = text
        current_job = nil
      end
      local job_id = text:match('%(ID (%d+)%)%s*$')
      if job_id then
        jobs[lnum] = { id = job_id, failed = status == 'failure' }
        current_job = jobs[lnum]
        job_lnums[#job_lnums + 1] = lnum
      elseif current_job and text:match('^%s+') and section ~= 'ANNOTATIONS' then
        jobs[lnum] = current_job
      end
    end
    lines[lnum] = text
    hls[lnum] = h
  end

  return { lines = lines, hls = hls, jobs = jobs, job_lnums = job_lnums }
end

local function summary_job_at_line(raw_lines, lnum)
  local first, last = 1, #raw_lines

  while first <= last do
    local text = strip_ansi(raw_lines[first])
    if not text:match('^%s*$') then
      break
    end
    first = first + 1
  end

  while last >= first do
    local text = strip_ansi(raw_lines[last])
    if not text:match('^%s*$') then
      break
    end
    last = last - 1
  end

  if lnum < first or lnum > last then
    return nil
  end

  return parse_summary(raw_lines).jobs[lnum - first + 1]
end

local function summary_hls(prefix, status)
  return { { col = 0, end_col = #prefix, group = summary_status_group(status) } }
end

local function parse_summary_json(data)
  local lines = {}
  local hls_list = {}
  local jobs = {}
  local job_lnums = {}

  local run_status = (data.conclusion and data.conclusion ~= '') and data.conclusion or data.status
  local header_prefix = summary_status_icon(run_status) .. '  '
  local header = header_prefix .. (data.displayTitle or data.name or 'run')
  lines[#lines + 1] = header
  hls_list[#hls_list + 1] = summary_hls(header_prefix, run_status)

  lines[#lines + 1] = ''
  hls_list[#hls_list + 1] = {}

  for _, job in ipairs(data.jobs or {}) do
    local jstatus = (job.conclusion and job.conclusion ~= '') and job.conclusion or job.status
    local prefix = summary_status_icon(jstatus) .. '  '
    local line = prefix .. (job.name or 'job')
    local dur = duration_label(format_duration(job.startedAt, job.completedAt))
    if dur then
      line = line .. '  ' .. dur
    end
    if jstatus == 'in_progress' and job.steps then
      local done, total = 0, 0
      for _, s in ipairs(job.steps) do
        total = total + 1
        local sc = (s.conclusion and s.conclusion ~= '') and s.conclusion or s.status
        if sc == 'success' or sc == 'failure' or sc == 'skipped' then
          done = done + 1
        end
      end
      if total > 0 then
        line = line .. ('  [%d/%d]'):format(done, total)
      end
    end
    lines[#lines + 1] = line
    hls_list[#hls_list + 1] = summary_hls(prefix, jstatus)

    local job_id = tostring(job.databaseId or '')
    if job_id ~= '' then
      local failed = jstatus == 'failure'
      jobs[#lines] = { id = job_id, failed = failed }
      job_lnums[#job_lnums + 1] = #lines
    end
  end

  return { lines = lines, hls = hls_list, jobs = jobs, job_lnums = job_lnums }
end

M.filter_summary = filter_summary
M.normalize_job_filter_input = normalize_job_filter_input
M.parse_summary = parse_summary
M.parse_summary_json = parse_summary_json
M.summary_job_at_line = summary_job_at_line

return M
