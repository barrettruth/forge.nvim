local M = {}

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
  local then_ = os.time({
    year = assert(tonumber(year)),
    month = assert(tonumber(month)),
    day = assert(tonumber(day)),
  })
  local days = math.floor(os.difftime(os.time(), then_) / 86400)
  if days <= 0 then
    return 'today'
  elseif days == 1 then
    return 'yesterday'
  elseif days < 30 then
    return days .. ' days ago'
  end
  return math.floor(days / 30) .. ' months ago'
end

--- @param lines string[]
--- @param body string?
function M.append_body(lines, body)
  for _, line in ipairs(vim.split(vim.trim(body or ''), '\n', { plain = true })) do
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
    lines[#lines + 1] = ('*%s (%s) — %s*'):format(
      vim.tbl_get(comment, 'author', 'login') or 'ghost',
      comment.authorAssociation or 'NONE',
      M.age(comment.createdAt)
    )
    lines[#lines + 1] = ''
    M.append_body(lines, comment.body)
  end
end

return M
