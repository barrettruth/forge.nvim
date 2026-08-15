local M = {}

--- @param t osdateparam
--- @return integer
local function from_utc(t)
  local guess = os.time(t)
  local round_tripped = os.date('!*t', guess) --[[@as osdateparam]]
  round_tripped.isdst = false
  return math.floor(guess + os.difftime(guess, os.time(round_tripped)))
end

--- @param epoch integer
--- @return integer
local function noon(epoch)
  local d = os.date('*t', epoch)
  return os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
end

--- How long ago, roughly. Precision past a month is not worth the words.
--- @param iso string?
--- @return string
function M.age(iso)
  if not iso then
    return 'unknown'
  end
  local year, month, day = iso:match('^(%d+)-(%d+)-(%d+)')
  if not year then
    return iso
  end
  local hour, min, sec = iso:match('T(%d+):(%d+):(%d+)')
  local then_ = from_utc({
    year = assert(tonumber(year)),
    month = assert(tonumber(month)),
    day = assert(tonumber(day)),
    hour = tonumber(hour) or 12,
    min = tonumber(min) or 0,
    sec = tonumber(sec) or 0,
  })
  local days = math.floor(os.difftime(noon(os.time()), noon(then_)) / 86400)
  if days <= 0 then
    return 'today'
  elseif days == 1 then
    return 'yesterday'
  elseif days < 30 then
    return days .. ' days ago'
  elseif days < 365 then
    local months = math.floor(days / 30)
    return months .. (months == 1 and ' month ago' or ' months ago')
  end
  local years = math.floor(days / 365)
  return years .. (years == 1 and ' year ago' or ' years ago')
end

--- @param lines string[]
--- @param body string?
function M.append_body(lines, body)
  local text = vim.trim(((body or ''):gsub('\r\n?', '\n')))
  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    lines[#lines + 1] = line
  end
end

--- Append a conversation, if there is one.
--- @param lines string[]
--- @param comments table?
function M.append_comments(lines, comments)
  if not comments then
    return
  end
  local nodes = comments.nodes or {}
  if #nodes == 0 then
    return
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = ('## Comments (%d)'):format(comments.totalCount or #nodes)
  for _, comment in ipairs(nodes) do
    lines[#lines + 1] = ''
    lines[#lines + 1] = ('### %s (%s) — %s'):format(
      vim.tbl_get(comment, 'author', 'login') or 'ghost',
      comment.authorAssociation or 'NONE',
      M.age(comment.createdAt)
    )
    lines[#lines + 1] = ''
    M.append_body(lines, comment.body)
  end
end

return M
