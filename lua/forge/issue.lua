local gh = require('forge.gh')
local log = require('forge.log')
local uri = require('forge.uri')

local M = {}

local NS = vim.api.nvim_create_namespace('forge')

local LIST_QUERY = [[
query($owner: String!, $repo: String!, $states: [IssueState!], $after: String) {
  repository(owner: $owner, name: $repo) {
    issues(
      first: 100
      states: $states
      after: $after
      orderBy: {field: UPDATED_AT, direction: DESC}
    ) {
      totalCount
      pageInfo { hasNextPage endCursor }
      nodes { number title }
    }
  }
}
]]

local PER_PAGE = 100

local ISSUE_QUERY = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      number title state body createdAt
      author { login }
      authorAssociation
      labels(first: 20) { totalCount nodes { name } }
      comments(first: 100) {
        totalCount
        nodes { author { login } authorAssociation createdAt body }
      }
    }
  }
}
]]

--- @param iso string?
--- @return string
local function age(iso)
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
local function append_body(lines, body)
  for _, line in ipairs(vim.split(vim.trim(body or ''), '\n', { plain = true })) do
    lines[#lines + 1] = line
  end
end

--- Show `lines` as the view named by `u`, reusing its buffer if it exists.
---
--- A single issue is markdown, because that is what GitHub gave us and
--- markdown already knows how to draw it. A list is not markdown, so it gets a
--- filetype of its own.
---
--- Mappings are set here rather than in an ftplugin: a viewer is markdown, and
--- an ftplugin/markdown.lua would reach every markdown file you open.
---
--- The buffer is replaced in place rather than wiped and rebuilt, so a window
--- handle held by a caller stays valid across a refresh.
--- @class forge.Mark
--- @field row integer zero-based
--- @field col integer byte column, inclusive
--- @field end_col integer byte column, exclusive
--- @field group string

--- @param u forge.Uri
--- @param lines string[]
--- @param winbar string
--- @param marks forge.Mark[]?
--- @return integer buf
local function render(u, lines, winbar, marks)
  local name = uri.tostring(u)
  local buf = vim.fn.bufnr(name)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buf, name)
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, mark in ipairs(marks or {}) do
    vim.api.nvim_buf_set_extmark(buf, NS, mark.row, mark.col, {
      end_col = mark.end_col,
      hl_group = mark.group,
    })
  end

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = u.kind == 'issue' and 'markdown' or 'forge'

  local map = require('forge.map')
  map.buf_default(buf, 'n', 'g?', '<Plug>(forge-help)', 'what the keys in this buffer do')
  map.buf_default(buf, 'n', '-', '<Plug>(forge-up)', 'go up to the issue list')
  map.buf_default(buf, 'n', 'R', '<Plug>(forge-refresh)', 'fetch this view again')
  map.buf_default(buf, 'n', 'gX', '<Plug>(forge-web)', 'open this view on github.com')
  if u.kind == 'issues' then
    map.buf_default(buf, 'n', '<CR>', '<Plug>(forge-issue-open)', 'open the issue under the cursor')
    map.buf_default(buf, 'n', 'o', '<Plug>(forge-issue-open-split)', 'open it in a split instead')
    map.buf_default(buf, 'n', ']i', '<Plug>(forge-issue-next-page)', 'the next page of issues')
    map.buf_default(buf, 'n', '[i', '<Plug>(forge-issue-prev-page)', 'the previous page of issues')
    map.buf_default(buf, 'n', 'g.', '<Plug>(forge-issue-state)', 'toggle open and closed issues')
  end

  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.b[buf].forge_winbar = winbar
  vim.wo.winbar = winbar
  return buf
end

--- Escape text bound for a 'winbar', where % introduces an item.
--- @param text string
--- @return string
local function escape(text)
  return (text:gsub('%%', '%%%%'))
end

--- Wrap 'winbar' text in a highlight group. An empty group is harmless.
--- @param group string
--- @param text string
--- @return string
local function hl(group, text)
  return ('%%#%s#%s%%*'):format(group, text)
end

--- Builtin groups, linked to nothing of our own: a state reads as ok or as a
--- problem, and those groups already mean that everywhere else in the editor.
local STATE_HL = { OPEN = 'OkMsg', CLOSED = 'ErrorMsg' }

--- Show one page of a repository's issues.
---
--- `cursors[n]` is what to ask GitHub for to reach page n, so paging backwards
--- costs nothing beyond remembering where each page began.
--- @param u forge.Uri
--- @param page integer
--- @param cursors table<integer, string>
local function open_list(u, page, cursors)
  local state = u.state == 'CLOSED' and 'closed' or 'open'
  local variables = { owner = u.owner, repo = u.repo, states = u.state or 'OPEN' }
  if cursors[page] then
    variables.after = cursors[page]
  end

  gh.graphql(
    ('%s/%s %s issues'):format(u.owner, u.repo, state),
    LIST_QUERY,
    variables,
    function(data)
      local issues = vim.tbl_get(data, 'repository', 'issues')
      if not issues then
        log.err(('no such repository: %s/%s'):format(u.owner, u.repo))
        return
      end

      local nodes = issues.nodes or {}
      local width = 1
      for _, issue in ipairs(nodes) do
        width = math.max(width, #tostring(issue.number))
      end
      local format = ('#%%-%dd %%s'):format(width)

      local lines, marks = {}, {}
      for _, issue in ipairs(nodes) do
        local row = #lines
        lines[row + 1] = format:format(issue.number, issue.title)
        marks[#marks + 1] =
          { row = row, col = 0, end_col = 1 + #tostring(issue.number), group = 'Tag' }
      end
      if #lines == 0 then
        lines = { ('No %s issues.'):format(state) }
        marks = { { row = 0, col = 0, end_col = #lines[1], group = 'Comment' } }
      end

      local info = issues.pageInfo or {}
      local total = issues.totalCount or #lines
      local pages = math.max(1, math.ceil(total / PER_PAGE))
      local winbar = table.concat({
        hl('Title', 'ISSUES'),
        hl('Directory', ('%s/%s'):format(escape(u.owner), escape(u.repo))),
        hl(STATE_HL[u.state or 'OPEN'] or '', state),
        ('%d/%d'):format(page, pages),
        hl('Comment', ('(%d)'):format(total)),
      }, ' ')

      local buf = render(u, lines, winbar, marks)
      if info.hasNextPage and info.endCursor then
        cursors[page + 1] = info.endCursor
      end
      vim.b[buf].forge = { page = page, cursors = cursors, has_next = info.hasNextPage or false }
    end
  )
end

--- The paging state a list buffer is carrying, if it is a list buffer.
--- @return forge.Uri?
--- @return table?
local function list_state()
  local u = uri.parse(vim.api.nvim_buf_get_name(0))
  if not u or u.kind ~= 'issues' then
    return nil, nil
  end
  return u, vim.b[vim.api.nvim_get_current_buf()].forge or { page = 1, cursors = {} }
end

--- Step `delta` pages through an issue list.
--- @param delta integer
function M.page(delta)
  local u, state = list_state()
  if not u or not state then
    return
  end
  local page = state.page + delta
  if page < 1 then
    log.info('already on the first page')
    return
  end
  if delta > 0 and not state.has_next then
    log.info('no more issues')
    return
  end
  open_list(u, page, state.cursors)
end

--- Swap an issue list between open and closed, from the first page.
function M.toggle_state()
  local u = list_state()
  if not u then
    return
  end
  u.state = u.state == 'CLOSED' and 'OPEN' or 'CLOSED'
  open_list(u, 1, {})
end

--- @param u forge.Uri
local function open_issue(u)
  gh.graphql(
    ('%s/%s#%d'):format(u.owner, u.repo, u.number),
    ISSUE_QUERY,
    { owner = u.owner, repo = u.repo, number = u.number },
    function(data)
      local issue = vim.tbl_get(data, 'repository', 'issue')
      if not issue then
        log.err(('no such issue: %s/%s#%d'):format(u.owner, u.repo, u.number))
        return
      end

      local labels = {}
      for _, label in ipairs(vim.tbl_get(issue, 'labels', 'nodes') or {}) do
        labels[#labels + 1] = label.name
      end

      local lines = {
        ('# %s'):format(issue.title),
        '',
        ('- Author: %s (%s)'):format(
          vim.tbl_get(issue, 'author', 'login') or 'ghost',
          issue.authorAssociation or 'NONE'
        ),
        ('- State: %s, opened %s'):format(issue.state or '?', age(issue.createdAt)),
      }
      if #labels > 0 then
        lines[#lines + 1] = ('- Labels: %s'):format(table.concat(labels, ', '))
      end
      lines[#lines + 1] = ''
      append_body(lines, issue.body)

      local comments = issue.comments or {}
      local nodes = comments.nodes or {}
      if #nodes > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('## Comments (%d)'):format(comments.totalCount or #nodes)
        for _, comment in ipairs(nodes) do
          lines[#lines + 1] = ''
          lines[#lines + 1] = ('*%s (%s) — %s*'):format(
            vim.tbl_get(comment, 'author', 'login') or 'ghost',
            comment.authorAssociation or 'NONE',
            age(comment.createdAt)
          )
          lines[#lines + 1] = ''
          append_body(lines, comment.body)
        end
      end

      local winbar = table.concat({
        hl('Title', 'ISSUE'),
        hl('Tag', '#' .. issue.number),
        hl(STATE_HL[issue.state] or '', issue.state or '?'),
        hl('Comment', '|'),
        escape(issue.title or '') .. '%<',
      }, ' ')
      render(u, lines, winbar)
      gh.check_truncated(comments, 'comments')
    end
  )
end

--- Open whatever `target` names.
--- @param target string?
function M.open(target)
  local u, err = uri.resolve(target)
  if not u then
    log.err(err or 'cannot resolve target')
    return
  end
  if u.kind == 'issue' then
    open_issue(u)
  else
    open_list(u, 1, {})
  end
end

--- Fetch this view again, where it stands.
---
--- Unlike |:edit|, which rebuilds a view from its name and so returns to the
--- first page, a refresh keeps the page you were on.
function M.refresh()
  local u = uri.parse(vim.api.nvim_buf_get_name(0))
  if not u then
    return
  end
  if u.kind == 'issue' then
    open_issue(u)
    return
  end
  local state = vim.b[vim.api.nvim_get_current_buf()].forge or { page = 1, cursors = {} }
  open_list(u, state.page, state.cursors)
end

--- Open this view on github.com.
---
--- What is shown, not what the cursor is on: the buffer already knows what it
--- is, and <CR> is how you follow a line.
function M.web()
  local u = uri.parse(vim.api.nvim_buf_get_name(0))
  if not u then
    log.warn('no url for this buffer')
    return
  end
  vim.ui.open(uri.web(u))
end

--- Leave an issue for the list it belongs to.
---
--- The list is the top: there is nothing above it to go up to.
function M.up()
  local u = uri.parse(vim.api.nvim_buf_get_name(0))
  if not u or u.kind ~= 'issue' then
    return
  end
  open_list({ owner = u.owner, repo = u.repo, kind = 'issues', state = 'OPEN' }, 1, {})
end

--- Open the issue under the cursor in an issue list.
--- @param split boolean? open it beside the list rather than over it
function M.open_at_cursor(split)
  local u = uri.parse(vim.api.nvim_buf_get_name(0))
  if not u or u.kind ~= 'issues' then
    return
  end
  local number = vim.api.nvim_get_current_line():match('^#(%d+)')
  if not number then
    return
  end
  if split then
    vim.cmd('split')
  end
  open_issue({ owner = u.owner, repo = u.repo, kind = 'issue', number = tonumber(number) })
end

return M
