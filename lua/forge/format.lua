local M = {}
local layout = require('forge.layout')

---@param s string
---@param width integer
---@return string
function M.pad_or_truncate(s, width)
  return layout.fit(s, width)
end

---@param iso string?
---@return integer?
function M.parse_iso(iso)
  if not iso or type(iso) ~= 'string' or iso == '' then
    return nil
  end
  local y, mo, d, h, mi, s = iso:match('(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
  if not y then
    return nil
  end
  local ok, ts = pcall(os.time, {
    year = tonumber(y) --[[@as integer]],
    month = tonumber(mo) --[[@as integer]],
    day = tonumber(d) --[[@as integer]],
    hour = tonumber(h) --[[@as integer]],
    min = tonumber(mi) --[[@as integer]],
    sec = tonumber(s) --[[@as integer]],
  })
  if ok and ts then
    return ts
  end
  return nil
end

---@param iso string?
---@return string
function M.relative_time(iso)
  local ts = M.parse_iso(iso)
  if not ts then
    return ''
  end
  local diff = os.time() - ts
  if diff < 0 then
    diff = 0
  end
  if diff < 3600 then
    return ('%dm'):format(math.max(1, math.floor(diff / 60)))
  end
  if diff < 86400 then
    return ('%dh'):format(math.floor(diff / 3600))
  end
  if diff < 2592000 then
    return ('%dd'):format(math.floor(diff / 86400))
  end
  if diff < 31536000 then
    return ('%dmo'):format(math.floor(diff / 2592000))
  end
  return ('%dy'):format(math.floor(diff / 31536000))
end

local event_map = {
  merge_request_event = 'mr',
  external_pull_request_event = 'ext',
  pull_request = 'pr',
  workflow_dispatch = 'manual',
  schedule = 'cron',
  pipeline = 'child',
  push = 'push',
  web = 'web',
  api = 'api',
  trigger = 'trigger',
}

---@param event string
---@return string
function M.abbreviate_event(event)
  return event_map[event] or event
end

---@param entry table
---@param field string
---@return string
function M.extract_author(entry, field)
  local v = entry[field]
  if type(v) == 'table' then
    return v.login or v.username or v.name or ''
  end
  return tostring(v or '')
end

---@param secs integer
---@return string
function M.format_duration(secs)
  if secs < 0 then
    secs = 0
  end
  if secs >= 3600 then
    return ('%dh%dm'):format(math.floor(secs / 3600), math.floor(secs % 3600 / 60))
  end
  if secs >= 60 then
    return ('%dm%ds'):format(math.floor(secs / 60), secs % 60)
  end
  return ('%ds'):format(secs)
end

local function elastic_width(preferred, values, min, opts)
  return layout.elastic(preferred, layout.measure(values, opts), min)
end

local function pr_state_icon(icons, state)
  state = (state or ''):lower()
  if state == 'open' or state == 'opened' then
    return icons.open, 'ForgeOpen'
  end
  if state == 'merged' then
    return icons.merged, 'ForgeMerged'
  end
  return icons.closed, 'ForgeClosed'
end

local function issue_state_icon(icons, state)
  state = (state or ''):lower()
  if state == 'open' or state == 'opened' then
    return icons.open, 'ForgeOpen'
  end
  return icons.closed, 'ForgeClosed'
end

local function check_bucket_icon(icons, bucket)
  bucket = (bucket or 'pending'):lower()
  if bucket == 'pass' then
    return icons.pass, 'ForgePass'
  end
  if bucket == 'fail' then
    return icons.fail, 'ForgeFail'
  end
  if bucket == 'pending' then
    return icons.pending, 'ForgePending'
  end
  if bucket == 'skipping' or bucket == 'cancel' then
    return icons.skip, 'ForgeSkip'
  end
  return icons.unknown, 'ForgeSkip'
end

local function run_status_icon(icons, status)
  status = (status or ''):lower()
  if status == 'success' then
    return icons.pass, 'ForgePass'
  end
  if status == 'failure' or status == 'failed' then
    return icons.fail, 'ForgeFail'
  end
  if
    status == 'in_progress'
    or status == 'running'
    or status == 'pending'
    or status == 'queued'
  then
    return icons.pending, 'ForgePending'
  end
  if status == 'cancelled' or status == 'canceled' or status == 'skipped' then
    return icons.skip, 'ForgeSkip'
  end
  return icons.unknown, 'ForgeSkip'
end

local function release_state_icon(icons, is_draft, is_pre, is_latest)
  if is_draft then
    return icons.pending, 'ForgePending'
  end
  if is_pre then
    return icons.skip, 'ForgeSkip'
  end
  if is_latest then
    return icons.pass, 'ForgePass'
  end
  return icons.open, 'ForgeOpen'
end

local function elapsed_for(check)
  local ts = M.parse_iso(check.startedAt)
  local te = M.parse_iso(check.completedAt)
  if ts and te then
    return M.format_duration(te - ts)
  end
  return ''
end

local function pr_issue_rows(entries, fields, show_state, opts, icon_fn)
  local display = require('forge.config').config().display
  local icons = display.icons
  local widths = display.widths
  local numbers = {}
  local titles = {}
  local authors = {}
  local ages = {}
  for _, entry in ipairs(entries) do
    numbers[#numbers + 1] = '#' .. tostring(entry[fields.number] or '')
    titles[#titles + 1] = entry[fields.title] or ''
    authors[#authors + 1] = M.extract_author(entry, fields.author)
    ages[#ages + 1] = M.relative_time(entry[fields.created_at])
  end
  local title_pref, title_max = elastic_width(widths.title, titles, 12)
  local author_pref, author_max = elastic_width(widths.author, authors, 6)
  local plan = layout.plan({
    width = opts and opts.width or layout.picker_width(),
    columns = {
      { key = 'state', fixed = show_state and 1 or 0 },
      {
        key = 'number',
        gap = show_state and '  ' or '',
        fixed = math.max(2, layout.max_width(numbers)),
      },
      {
        key = 'title',
        gap = ' ',
        min = 12,
        preferred = title_pref,
        max = title_max,
        shrink = 2,
        grow = 1,
        overflow = 'tail',
        pack_on = 'compact',
      },
      {
        key = 'author',
        gap = ' ',
        min = 6,
        preferred = author_pref,
        max = author_max,
        optional = true,
        drop = 2,
        shrink = 1,
        grow = 2,
        overflow = 'tail',
        hide_if_empty = true,
      },
      {
        key = 'age',
        gap = ' ',
        fixed = layout.max_width(ages),
        optional = true,
        drop = 1,
        hide_if_empty = true,
      },
    },
  })
  local rows = {}
  for i, entry in ipairs(entries) do
    local icon, group = icon_fn(icons, entry[fields.state])
    rows[i] = layout.render(plan, {
      state = { icon, group },
      number = { numbers[i], 'ForgeNumber' },
      title = titles[i],
      author = { authors[i], 'ForgeDim' },
      age = { ages[i], 'ForgeDim' },
    })
  end
  return rows
end

function M.format_prs(entries, fields, show_state, opts)
  return pr_issue_rows(entries, fields, show_state, opts, pr_state_icon)
end

function M.format_issues(entries, fields, show_state, opts)
  return pr_issue_rows(entries, fields, show_state, opts, issue_state_icon)
end

function M.format_checks(checks, opts)
  local display = require('forge.config').config().display
  local icons = display.icons
  local widths = display.widths
  local names = {}
  local elapsed = {}
  for _, check in ipairs(checks) do
    names[#names + 1] = check.name or ''
    elapsed[#elapsed + 1] = elapsed_for(check)
  end
  local name_pref, name_max = elastic_width(widths.name, names, 10)
  local plan = layout.plan({
    width = opts and opts.width or layout.picker_width(),
    columns = {
      { key = 'state', fixed = 1 },
      {
        key = 'name',
        gap = '  ',
        min = 10,
        preferred = name_pref,
        max = name_max,
        shrink = 2,
        grow = 1,
        overflow = 'tail',
        pack_on = 'compact',
      },
      {
        key = 'elapsed',
        gap = ' ',
        fixed = layout.max_width(elapsed),
        optional = true,
        drop = 1,
        hide_if_empty = true,
      },
    },
  })
  local rows = {}
  for i, check in ipairs(checks) do
    local icon, group = check_bucket_icon(icons, check.bucket)
    rows[i] = layout.render(plan, {
      state = { icon, group },
      name = names[i],
      elapsed = { elapsed[i], 'ForgeDim' },
    })
  end
  return rows
end

function M.format_runs(runs, opts)
  local display = require('forge.config').config().display
  local icons = display.icons
  local widths = display.widths
  local names = {}
  local branches = {}
  local events = {}
  local ages = {}
  for _, run in ipairs(runs) do
    names[#names + 1] = run.name or ''
    branches[#branches + 1] = run.branch or ''
    events[#events + 1] = M.abbreviate_event(run.event)
    ages[#ages + 1] = M.relative_time(run.created_at)
  end
  local name_pref, name_max = elastic_width(widths.name, names, 10)
  local branch_pref, branch_max = elastic_width(widths.branch, branches, 8)
  local plan = layout.plan({
    width = opts and opts.width or layout.picker_width(),
    columns = {
      { key = 'state', fixed = 1 },
      {
        key = 'name',
        gap = '  ',
        min = 10,
        preferred = name_pref,
        max = name_max,
        shrink = 3,
        grow = 1,
        overflow = 'tail',
        pack_on = 'compact',
      },
      {
        key = 'branch',
        gap = ' ',
        min = 8,
        preferred = branch_pref,
        max = branch_max,
        optional = true,
        drop = 3,
        shrink = 2,
        grow = 2,
        overflow = 'tail',
        pack_on = 'compact',
        hide_if_empty = true,
      },
      {
        key = 'event',
        gap = ' ',
        fixed = layout.max_width(events),
        optional = true,
        drop = 1,
        hide_if_empty = true,
      },
      {
        key = 'age',
        gap = ' ',
        fixed = layout.max_width(ages),
        optional = true,
        drop = 2,
        hide_if_empty = true,
      },
    },
  })
  local rows = {}
  for i, run in ipairs(runs) do
    local icon, group = run_status_icon(icons, run.status)
    rows[i] = layout.render(plan, {
      state = { icon, group },
      name = names[i],
      branch = { branches[i], 'ForgeBranch' },
      event = { events[i], 'ForgeDim' },
      age = { ages[i], 'ForgeDim' },
    })
  end
  return rows
end

function M.format_releases(entries, fields, opts)
  local display = require('forge.config').config().display
  local icons = display.icons
  local widths = display.widths
  local tags = {}
  local titles = {}
  local ages = {}
  local states = {}
  for _, entry in ipairs(entries) do
    local tag = entry[fields.tag] or ''
    local title = entry[fields.title] or ''
    tags[#tags + 1] = tag
    titles[#titles + 1] = title ~= '' and title ~= tag and title or ''
    ages[#ages + 1] = M.relative_time(entry[fields.published_at])
    states[#states + 1] = {
      entry[fields.is_draft],
      entry[fields.is_prerelease],
      entry[fields.is_latest],
    }
  end
  local tag_pref, tag_max = elastic_width(20, tags, 6)
  local title_pref, title_max = elastic_width(widths.title, titles, 10)
  local plan = layout.plan({
    width = opts and opts.width or layout.picker_width(),
    columns = {
      { key = 'state', fixed = 1 },
      {
        key = 'tag',
        gap = '  ',
        min = 6,
        preferred = tag_pref,
        max = tag_max,
        shrink = 2,
        grow = 2,
        overflow = 'tail',
      },
      {
        key = 'title',
        gap = ' ',
        min = 10,
        preferred = title_pref,
        max = title_max,
        optional = true,
        drop = 2,
        shrink = 1,
        grow = 1,
        overflow = 'tail',
        pack_on = 'compact',
        hide_if_empty = true,
      },
      {
        key = 'age',
        gap = ' ',
        fixed = layout.max_width(ages),
        optional = true,
        drop = 1,
        hide_if_empty = true,
      },
    },
  })
  local rows = {}
  for i = 1, #entries do
    local icon, group = release_state_icon(icons, states[i][1], states[i][2], states[i][3])
    rows[i] = layout.render(plan, {
      state = { icon, group },
      tag = { tags[i], 'ForgeBranch' },
      title = titles[i],
      age = { ages[i], 'ForgeDim' },
    })
  end
  return rows
end

---@param entry table
---@param fields table
---@param show_state boolean
---@return forge.Segment[]
function M.format_pr(entry, fields, show_state, opts)
  return M.format_prs({ entry }, fields, show_state, opts)[1]
end

---@param entry table
---@param fields table
---@param show_state boolean
---@return forge.Segment[]
function M.format_issue(entry, fields, show_state, opts)
  return M.format_issues({ entry }, fields, show_state, opts)[1]
end

---@param check table
---@return forge.Segment[]
function M.format_check(check, opts)
  return M.format_checks({ check }, opts)[1]
end

---@param run forge.CIRun
---@return forge.Segment[]
function M.format_run(run, opts)
  return M.format_runs({ run }, opts)[1]
end

---@param entry table
---@param fields table
---@return forge.Segment[]
function M.format_release(entry, fields, opts)
  return M.format_releases({ entry }, fields, opts)[1]
end

---@param checks table[]
---@param filter string?
---@return table[]
function M.filter_checks(checks, filter)
  if not filter or filter == 'all' then
    table.sort(checks, function(a, b)
      local order = { fail = 1, pending = 2, pass = 3, skipping = 4, cancel = 5 }
      local oa = order[(a.bucket or ''):lower()] or 9
      local ob = order[(b.bucket or ''):lower()] or 9
      return oa < ob
    end)
    return checks
  end
  local filtered = {}
  for _, c in ipairs(checks) do
    if (c.bucket or ''):lower() == filter then
      table.insert(filtered, c)
    end
  end
  return filtered
end

---@param runs forge.CIRun[]
---@param filter string?
---@return forge.CIRun[]
function M.filter_runs(runs, filter)
  local bucket_for = function(run)
    local status = (run.status or ''):lower()
    if status == 'success' then
      return 'pass'
    end
    if status == 'failure' or status == 'failed' then
      return 'fail'
    end
    if
      status == 'in_progress'
      or status == 'running'
      or status == 'pending'
      or status == 'queued'
    then
      return 'pending'
    end
    if status == 'cancelled' or status == 'canceled' or status == 'skipped' then
      return 'cancel'
    end
    return 'skipping'
  end

  if not filter or filter == 'all' then
    table.sort(runs, function(a, b)
      local order = { fail = 1, pending = 2, pass = 3, cancel = 4, skipping = 5 }
      local oa = order[bucket_for(a)] or 9
      local ob = order[bucket_for(b)] or 9
      return oa < ob
    end)
    return runs
  end

  local filtered = {}
  for _, run in ipairs(runs) do
    if bucket_for(run) == filter then
      table.insert(filtered, run)
    end
  end
  return filtered
end

return M
