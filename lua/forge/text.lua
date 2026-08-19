local M = {}

--- Read a UTC timestamp table as an epoch. `os.time` reads a table as local.
---
--- The round trip has to carry the daylight saving in force at that instant.
--- `os.date('!*t')` reports isdst false. UTC has none. Reading that back as
--- local picks the standard offset, an hour out all summer. An item opened
--- minutes ago then reads "yesterday" before local midnight.
--- @param t osdateparam
--- @return integer
local function from_utc(t)
  local guess = os.time(t)
  local round_tripped = os.date('!*t', guess) --[[@as osdateparam]]
  round_tripped.isdst = os.date('*t', guess).isdst
  return math.floor(guess + os.difftime(guess, os.time(round_tripped)))
end

--- Midday. Two of these subtract to calendar days, not 24-hour spans.
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

--- What starts a comment. Not a heading. A body is markdown and can spell one
--- itself, which would read as another comment starting. guh uses the same
--- bar.
local BAR = '▎'

--- A login wherever one appears. A label or a milestone is `Tag`. Everything
--- structural is `Comment`. Underline is added on top wherever a thing can be
--- followed. What a thing is and what it does are said separately.
M.LOGIN = '@markup.italic'
local LINK = '@markup.link'

--- Where |gx| goes from a login. forge has no view of a person, and every
--- forge puts one at the root of its own host.
--- @param login string
--- @return string
local function profile(login)
  return ('https://%s/%s'):format(M.host or 'github.com', login)
end

--- The view whose bodies are being drawn. Set for the length of a render: a
--- renderer takes no view of its own.
---
--- `host` is where a mention goes, which is the one thing in a body that
--- leaves for a host rather than for another view. The other two shorten an
--- address the forge would have shortened itself.
--- @type string?
M.host = nil
--- @type string?
M.project = nil
--- @type (fun(url: string, project: string): string?)?
M.shorten = nil

--- Trailing punctuation prose wraps an address in, which is never part of it.
local TRAILING = '[%.,;:%)%]}]+$'

--- What github links inside a body someone wrote, in the order ties are won.
---
--- The qualified form comes before the bare one. "o/r#4" is one reference,
--- not a repository with another inside it. "!123" is gitlab's, and marking
--- it everywhere costs nothing. github writes no such reference.
local INLINE = {
  { pattern = '@([%w][%w%-]*)', group = { M.LOGIN, LINK }, url = profile },
  { pattern = '[%w._%-]+/[%w._%-]+[#!]%d+', group = { 'Tag', LINK } },
  { pattern = '[#!]%d+', group = { 'Tag', LINK } },
}

--- Draw each of the forge's own addresses as short as the forge draws it.
---
--- The line is rewritten rather than concealed. A concealed range still takes
--- its full width when Neovim decides where to wrap, so a body that wraps
--- would break mid-sentence for no reason a reader can see. What is written
--- is a reference, so |gf| follows it; the address itself stays on the mark
--- for |gx|, and `b:forge.edit` still holds the body as it was written.
--- @param line string
--- @param row integer
--- @param marks forge.Mark[]
--- @return string line
--- @return table<integer, boolean> taken the columns it claimed
local function shortened(line, row, marks)
  local taken = {}
  if not M.shorten or not M.project then
    return line, taken
  end
  local out, at, col = {}, 1, 0
  while true do
    local from, to = line:find('https://%S+', at)
    if not from then
      break
    end
    local url = (line:sub(from, to):gsub(TRAILING, ''))
    -- Only the host that answered for this view, and never inside a code
    -- span. Any other address is somebody else's to spell.
    local _, ticks = line:sub(1, from - 1):gsub('`', '')
    local said = ticks % 2 == 0
        and url:match('^https://([^/]+)/') == M.host
        and M.shorten(url, M.project)
      or nil

    local before = line:sub(at, from - 1)
    out[#out + 1] = before
    col = col + #before
    out[#out + 1] = said or line:sub(from, to)
    if said then
      marks[#marks + 1] =
        { row = row, col = col, end_col = col + #said, group = { 'Tag', LINK }, url = url }
      for i = col + 1, col + #said do
        taken[i] = true
      end
    end
    col = col + #out[#out]
    at = said and (from + #url) or (to + 1)
  end
  out[#out + 1] = line:sub(at)
  return table.concat(out), taken
end

--- Mark what github would have linked in a line of prose.
--- @param line string
--- @param row integer
--- @param marks forge.Mark[]
--- @param taken table<integer, boolean>? columns an address already claimed
local function inline(line, row, marks, taken)
  taken = taken or {}
  for _, kind in ipairs(INLINE) do
    local from = 1
    while true do
      local at, to, name = line:find(kind.pattern, from)
      if not at or not to then
        break
      end
      from = to + 1
      -- Not mid-word, and not inside something already claimed. An email
      -- address is no mention. "abc#1" is no reference.
      local edge = at == 1 or not line:sub(at - 1, at - 1):match('[%w_]')
      if edge and not taken[at] then
        for i = at, to do
          taken[i] = true
        end
        marks[#marks + 1] = {
          row = row,
          col = at - 1,
          end_col = to,
          group = kind.group,
          url = kind.url and kind.url(name) or nil,
        }
      end
    end
  end
end

--- Append a body, or `instead` if there is none.
---
--- Substituted at render, never stored. `b:forge.edit` reads the same field.
--- The placeholder must not become the text you edit.
--- @param lines string[]
--- @param marks forge.Mark[]
--- @param body string?
--- @param instead string? what the forge says of an empty one, if anything
function M.append_body(lines, marks, body, instead)
  local text = vim.trim(((body or ''):gsub('\r\n?', '\n')))
  if text == '' then
    if instead then
      marks[#marks + 1] = { row = #lines, col = 0, end_col = #instead, group = 'Comment' }
      lines[#lines + 1] = instead
    end
    return
  end
  -- github links nothing inside a fence, and "@param" in one is not a person.
  local fenced = false
  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    local row = #lines
    if line:match('^%s*```') or line:match('^%s*~~~') then
      fenced = not fenced
      lines[row + 1] = line
    elseif fenced then
      lines[row + 1] = line
    else
      local shown, taken = shortened(line, row, marks)
      lines[row + 1] = shown
      inline(shown, row, marks, taken)
    end
  end
end

--- @class forge.Row
--- @field key string what it is, said in the plural github allows
--- @field values string[] what it is, empty for a row not worth drawing
--- @field group string the group its values take
--- @field link? fun(value: string): string where |gx| goes from one

--- The logins in a connection, in the order github gave them.
--- @param connection table?
--- @return string[]
function M.logins(connection)
  local out = {}
  -- By type throughout. A null in a list stays `vim.NIL`, which is truthy.
  local nodes = type(connection) == 'table' and connection.nodes or nil
  for _, node in ipairs(type(nodes) == 'table' and nodes or {}) do
    -- A requested reviewer is a user, a team or a mannequin.
    local name = type(node) == 'table'
      and (node.login or node.name or vim.tbl_get(node, 'author', 'login'))
    if name then
      out[#out + 1] = name
    end
  end
  return out
end

--- One message, in the shape this file draws rather than the shape a forge
--- answered in. An item's own description is one of these too. github dates
--- and attributes it like a comment.
--- @class forge.Comment
--- @field author string who wrote it, by login
--- @field association string? what they are to the project, where they are
--- anything to it
--- @field created_at string? when they wrote it, as an ISO 8601 timestamp
--- @field body string? what they wrote

--- Who wrote a thing and when, on one line. The same line for an item as for a
--- comment under it.
--- @param lines string[]
--- @param marks forge.Mark[]
--- @param comment forge.Comment
function M.append_author(lines, marks, comment)
  -- NONE is what github calls a passer-by, and is not worth drawing.
  local association = comment.association
  local who = comment.author
  local meta = {}
  if association and association ~= 'NONE' then
    meta[#meta + 1] = association
  end
  meta[#meta + 1] = M.age(comment.created_at)

  local row = #lines
  lines[row + 1] = ('%s %s  %s'):format(BAR, who, table.concat(meta, '  '))
  local said = #BAR + 1
  marks[#marks + 1] = { row = row, col = 0, end_col = #BAR, group = 'Comment' }
  marks[#marks + 1] = {
    row = row,
    col = said,
    end_col = said + #who,
    group = { M.LOGIN, LINK },
    url = profile(who),
  }
  marks[#marks + 1] =
    { row = row, col = said + #who + 2, end_col = #lines[row + 1], group = 'Comment' }
end

--- Append what is known about an item, a row to a line, aligned in a column.
--- An empty row is not drawn. The column is only as wide as what is there.
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
      said[#said + 1] =
        { key = row.key .. ':', values = values, group = row.group, link = row.link }
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
    -- Each value its own mark. One that can be followed carries the url. The
    -- comma between two of them stays unmarked.
    for _, value in ipairs(row.values) do
      marks[#marks + 1] = {
        row = at,
        col = col,
        end_col = col + #value,
        group = row.link and { row.group, LINK } or row.group,
        url = row.link and row.link(value) or nil,
      }
      col = col + #value + 2
    end
  end
end

--- Which pull request each drawn line of a stack names, for the keys that walk
--- one. Read by line rather than matched by pattern: a body may hold anything.
--- @class forge.stack.Rows
--- @field rows table<integer, integer> the pull request a row names, zero-based
--- @field order integer[] top first, as drawn
--- @field at integer where in `order` the one being read sits

--- Append the chain an item belongs to, if it belongs to one.
---
--- Drawn top first, the way github's own stack map and |jj| draw one, while the
--- count stays the forge's and is taken from the bottom. So the line marked in
--- a stack of four at 3/4 is the second from the top.
--- @param lines string[]
--- @param marks forge.Mark[]
--- @param held forge.Stack?
--- @param sigil string
--- @param group fun(pull: forge.stack.Pull): string the group its number takes
--- @return forge.stack.Rows?
function M.append_stack(lines, marks, held, sigil, group)
  if not held then
    return nil
  end
  local width = 1
  for _, layer in ipairs(held.layers) do
    width = math.max(width, #tostring(layer.number))
  end

  lines[#lines + 1] = ''
  lines[#lines + 1] = ('## Stack (%d/%d)'):format(held.position, #held.layers)
  lines[#lines + 1] = ''

  -- Above the layers, because that is where the fork is.
  if held.forks then
    local said = vim.tbl_map(function(number)
      return sigil .. number
    end, held.forks)
    local row = #lines
    local lead = '  forks above into '
    lines[row + 1] = lead .. table.concat(said, ', ')
    marks[#marks + 1] = { row = row, col = 0, end_col = #lines[row + 1], group = 'Comment' }
    local col = #lead
    for _, one in ipairs(said) do
      marks[#marks + 1] = { row = row, col = col, end_col = col + #one, group = 'Tag' }
      col = col + #one + 2
    end
  end

  --- @type forge.stack.Rows
  local nav = { rows = {}, order = {}, at = #held.layers - held.position + 1 }
  for i = #held.layers, 1, -1 do
    local layer = held.layers[i]
    local row = #lines
    local tag = sigil .. layer.number
    lines[row + 1] = ('  %s%s  %s'):format(
      tag,
      (' '):rep(width - #tostring(layer.number)),
      layer.title
    )
    marks[#marks + 1] = { row = row, col = 2, end_col = 2 + #tag, group = group(layer) }
    -- The one being read is said with the line rather than a character, as a
    -- list says a state with the colour of its number and nothing else.
    if i == held.position then
      marks[#marks + 1] = { row = row, line = 'CursorLine' }
    end
    nav.rows[row] = layer.number
    nav.order[#nav.order + 1] = layer.number
  end
  return nav
end

--- Append a conversation, if there is one. The heading counts what was
--- written, not what came. A capped connection still says how many there are.
--- @param lines string[]
--- @param marks forge.Mark[]
--- @param comments forge.Comment[]?
--- @param total integer? how many were written in all, when that is more
--- than were handed over
function M.append_comments(lines, marks, comments, total)
  if not comments or #comments == 0 then
    return
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = ('## Comments (%d)'):format(total or #comments)
  for _, comment in ipairs(comments) do
    lines[#lines + 1] = ''
    M.append_author(lines, marks, comment)
    lines[#lines + 1] = ''
    M.append_body(lines, marks, comment.body)
  end
end

return M
