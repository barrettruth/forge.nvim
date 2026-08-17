local M = {}

--- github's timestamps are UTC; `os.time` reads a table as local.
---
--- The round trip has to carry the daylight saving in force at that instant.
--- `os.date('!*t')` reports isdst false, because UTC has none, and reading that
--- back as local picks the standard offset — an hour out for as long as summer
--- time lasts, which shows up as an item opened minutes ago reading "yesterday"
--- for the hour before local midnight.
--- @param t osdateparam
--- @return integer
local function from_utc(t)
  local guess = os.time(t)
  local round_tripped = os.date('!*t', guess) --[[@as osdateparam]]
  round_tripped.isdst = os.date('*t', guess).isdst
  return math.floor(guess + os.difftime(guess, os.time(round_tripped)))
end

--- Midday, so that two of these subtract to calendar days and not 24-hour spans.
--- @param epoch integer
--- @return integer
local function noon(epoch)
  local d = os.date('*t', epoch)
  return os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
end

--- How long ago, in words for the first month and as a date after that.
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
  end
  return os.date('%Y-%m-%d', then_) --[[@as string]]
end

--- Append a body, or `instead` if there is none.
---
--- The caller supplies the words: github has some for an item and none for a
--- review. Substituted at render, since `b:forge.edit` reads the same field.
--- @param lines string[]
--- @param marks forge.Mark[]
--- @param body string?
--- @param instead string? what github says of an empty one, where it says any
function M.append_body(lines, marks, body, instead)
  local text = vim.trim(((body or ''):gsub('\r\n?', '\n')))
  if text == '' then
    if instead then
      marks[#marks + 1] = { row = #lines, col = 0, end_col = #instead, group = 'Comment' }
      lines[#lines + 1] = instead
    end
    return
  end
  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    lines[#lines + 1] = line
  end
end

--- What starts a comment. Not a heading: a body is markdown and can spell one
--- itself, which would read as another comment starting. guh uses the same
--- bar, and searches back for it to say which comment the cursor is in.
local BAR = '▎'

--- A login wherever one appears. A label or a milestone is `Tag`, and
--- everything structural is `Comment`.
M.LOGIN = '@markup.italic'

--- @class forge.Row
--- @field key string what it is, said in the plural github allows
--- @field values string[] what it is, empty for a row not worth drawing
--- @field group string the group its values take

--- The logins in a connection, in the order github gave them.
--- @param connection table?
--- @return string[]
function M.logins(connection)
  local out = {}
  --- By type throughout: a null in a list stays `vim.NIL`, which is truthy.
  local nodes = type(connection) == 'table' and connection.nodes or nil
  for _, node in ipairs(type(nodes) == 'table' and nodes or {}) do
    --- A requested reviewer is a user, a team or a mannequin.
    local name = type(node) == 'table'
      and (node.login or node.name or vim.tbl_get(node, 'author', 'login'))
    if name then
      out[#out + 1] = name
    end
  end
  return out
end

--- Who wrote a thing and when, on one line.
---
--- The same line for an item as for a comment under it, github treating a
--- description as authored and dated like one. Only the login is emphasised.
--- @param lines string[]
--- @param marks forge.Mark[]
--- @param node table anything with an author, an association and a createdAt
function M.append_author(lines, marks, node)
  --- NONE is what github calls a passer-by, and worth saying nothing about.
  local association = node.authorAssociation
  local who = vim.tbl_get(node, 'author', 'login') or 'ghost'
  local meta = {}
  if association and association ~= 'NONE' then
    meta[#meta + 1] = association
  end
  meta[#meta + 1] = M.age(node.createdAt)

  local row = #lines
  lines[row + 1] = ('%s %s  %s'):format(BAR, who, table.concat(meta, '  '))
  local said = #BAR + 1
  marks[#marks + 1] = { row = row, col = 0, end_col = #BAR, group = 'Comment' }
  marks[#marks + 1] = { row = row, col = said, end_col = said + #who, group = '@markup.italic' }
  marks[#marks + 1] =
    { row = row, col = said + #who + 2, end_col = #lines[row + 1], group = 'Comment' }
end

--- Append what is known about an item, a row to a line, aligned in a column.
---
--- An empty row is not drawn, so the column is only as wide as what is there.
--- @param lines string[]
--- @param marks forge.Mark[]
--- @param rows forge.Row[]
function M.append_rows(lines, marks, rows)
  local said = {}
  local width = 0
  for _, row in ipairs(rows) do
    local values = vim.tbl_filter(function(v)
      return v ~= nil and v ~= ''
    end, row.values or {})
    if #values > 0 then
      said[#said + 1] = { key = row.key .. ':', values = values, group = row.group }
      width = math.max(width, #row.key + 1)
    end
  end

  for _, row in ipairs(said) do
    local at = #lines
    local col = 2 + width + 2
    lines[at + 1] = ('  %s%s%s'):format(
      row.key,
      (' '):rep(col - 2 - #row.key),
      table.concat(row.values, ', ')
    )
    marks[#marks + 1] = { row = at, col = 0, end_col = 2 + #row.key, group = 'Comment' }
    marks[#marks + 1] = { row = at, col = col, end_col = #lines[at + 1], group = row.group }
  end
end

--- Append a conversation, if there is one.
--- @param lines string[]
--- @param marks forge.Mark[]
--- @param comments table?
function M.append_comments(lines, marks, comments)
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
    M.append_author(lines, marks, comment)
    lines[#lines + 1] = ''
    M.append_body(lines, marks, comment.body)
  end
end

return M
