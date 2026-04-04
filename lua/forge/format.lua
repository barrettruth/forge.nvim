local M = {}

---@param s string
---@param width integer
---@return string
function M.pad_or_truncate(s, width)
  local len = #s
  if len > width then
    return s:sub(1, width - 1) .. '…'
  end
  return s .. string.rep(' ', width - len)
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

---@param entry table
---@param fields table
---@param show_state boolean
---@return forge.Segment[]
function M.format_pr(entry, fields, show_state)
  local display = require('forge.config').config().display
  local icons = display.icons
  local widths = display.widths
  local num = tostring(entry[fields.number] or '')
  local title = entry[fields.title] or ''
  local author = M.extract_author(entry, fields.author)
  local age = M.relative_time(entry[fields.created_at])
  local segments = {}
  if show_state then
    local state = (entry[fields.state] or ''):lower()
    local icon, group
    if state == 'open' or state == 'opened' then
      icon, group = icons.open, 'ForgeOpen'
    elseif state == 'merged' then
      icon, group = icons.merged, 'ForgeMerged'
    else
      icon, group = icons.closed, 'ForgeClosed'
    end
    table.insert(segments, { icon, group })
    table.insert(segments, { '  ' })
  end
  table.insert(segments, { ('#%-5s'):format(num), 'ForgeNumber' })
  table.insert(segments, { ' ' .. M.pad_or_truncate(title, widths.title) .. ' ' })
  table.insert(segments, {
    M.pad_or_truncate(author, widths.author) .. (' %3s'):format(age),
    'ForgeDim',
  })
  return segments
end

---@param entry table
---@param fields table
---@param show_state boolean
---@return forge.Segment[]
function M.format_issue(entry, fields, show_state)
  local display = require('forge.config').config().display
  local icons = display.icons
  local widths = display.widths
  local num = tostring(entry[fields.number] or '')
  local title = entry[fields.title] or ''
  local author = M.extract_author(entry, fields.author)
  local age = M.relative_time(entry[fields.created_at])
  local segments = {}
  if show_state then
    local state = (entry[fields.state] or ''):lower()
    local icon, group
    if state == 'open' or state == 'opened' then
      icon, group = icons.open, 'ForgeOpen'
    else
      icon, group = icons.closed, 'ForgeClosed'
    end
    table.insert(segments, { icon, group })
    table.insert(segments, { '  ' })
  end
  table.insert(segments, { ('#%-5s'):format(num), 'ForgeNumber' })
  table.insert(segments, { ' ' .. M.pad_or_truncate(title, widths.title) .. ' ' })
  table.insert(segments, {
    M.pad_or_truncate(author, widths.author) .. (' %3s'):format(age),
    'ForgeDim',
  })
  return segments
end

---@param check table
---@return forge.Segment[]
function M.format_check(check)
  local display = require('forge.config').config().display
  local icons = display.icons
  local widths = display.widths
  local bucket = (check.bucket or 'pending'):lower()
  local name = check.name or ''
  local icon, group
  if bucket == 'pass' then
    icon, group = icons.pass, 'ForgePass'
  elseif bucket == 'fail' then
    icon, group = icons.fail, 'ForgeFail'
  elseif bucket == 'pending' then
    icon, group = icons.pending, 'ForgePending'
  elseif bucket == 'skipping' or bucket == 'cancel' then
    icon, group = icons.skip, 'ForgeSkip'
  else
    icon, group = icons.unknown, 'ForgeSkip'
  end
  local elapsed = ''
  local ts = M.parse_iso(check.startedAt)
  local te = M.parse_iso(check.completedAt)
  if ts and te then
    elapsed = M.format_duration(te - ts)
  end
  return {
    { icon, group },
    { '  ' .. M.pad_or_truncate(name, widths.name) .. ' ' },
    { elapsed, 'ForgeDim' },
  }
end

---@param run forge.CIRun
---@return forge.Segment[]
function M.format_run(run)
  local display = require('forge.config').config().display
  local icons = display.icons
  local widths = display.widths
  local icon, group
  local s = run.status:lower()
  if s == 'success' then
    icon, group = icons.pass, 'ForgePass'
  elseif s == 'failure' or s == 'failed' then
    icon, group = icons.fail, 'ForgeFail'
  elseif s == 'in_progress' or s == 'running' or s == 'pending' or s == 'queued' then
    icon, group = icons.pending, 'ForgePending'
  elseif s == 'cancelled' or s == 'canceled' or s == 'skipped' then
    icon, group = icons.skip, 'ForgeSkip'
  else
    icon, group = icons.unknown, 'ForgeSkip'
  end
  local event = M.abbreviate_event(run.event)
  local age = M.relative_time(run.created_at)
  if run.branch ~= '' then
    local name_w = widths.name - widths.branch + 10
    return {
      { icon, group },
      { '  ' .. M.pad_or_truncate(run.name, name_w) .. ' ' },
      { M.pad_or_truncate(run.branch, widths.branch), 'ForgeBranch' },
      { ' ' .. ('%-6s'):format(event) .. ' ' .. age, 'ForgeDim' },
    }
  end
  return {
    { icon, group },
    { '  ' .. M.pad_or_truncate(run.name, widths.name) .. ' ' },
    { ('%-6s'):format(event) .. ' ' .. age, 'ForgeDim' },
  }
end

---@param entry table
---@param fields table
---@return forge.Segment[]
function M.format_release(entry, fields)
  local display = require('forge.config').config().display
  local icons = display.icons
  local widths = display.widths
  local tag = entry[fields.tag] or ''
  local title = entry[fields.title] or ''
  local is_draft = fields.is_draft and entry[fields.is_draft]
  local is_pre = fields.is_prerelease and entry[fields.is_prerelease]
  local is_latest = fields.is_latest and entry[fields.is_latest]
  local age = M.relative_time(entry[fields.published_at])

  local icon, group
  if is_draft then
    icon, group = icons.pending, 'ForgePending'
  elseif is_pre then
    icon, group = icons.skip, 'ForgeSkip'
  elseif is_latest then
    icon, group = icons.pass, 'ForgePass'
  else
    icon, group = icons.open, 'ForgeOpen'
  end

  local tag_w = 20
  local title_w = widths.title
  if title == '' or title == tag then
    title_w = 0
  end

  local segments = {
    { icon, group },
    { '  ' .. M.pad_or_truncate(tag, tag_w), 'ForgeBranch' },
  }
  if title_w > 0 then
    table.insert(segments, { ' ' .. M.pad_or_truncate(title, title_w) .. ' ' })
  else
    table.insert(segments, { ' ' })
  end
  table.insert(segments, { ('%3s'):format(age), 'ForgeDim' })
  return segments
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

return M
