local gh = require('forge.gh')
local log = require('forge.log')
local text = require('forge.text')
local uri = require('forge.uri')
local view = require('forge.view')

local M = {}

local LIST_QUERY = [[
query($owner: String!, $repo: String!, $states: [IssueState!], $after: String) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
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

local ISSUE_QUERY = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
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

local STATE_HL = { OPEN = 'OkMsg', CLOSED = 'ErrorMsg' }

local LIST_MAPS = {
  { '<CR>', '<Plug>(forge-open)', 'open the issue under the cursor' },
  { 'o', '<Plug>(forge-open-split)', 'open the issue under the cursor in a split' },
  { ']i', '<Plug>(forge-next-page)', 'the next page of issues' },
  { '[i', '<Plug>(forge-prev-page)', 'the previous page of issues' },
  { 'g.', '<Plug>(forge-state)', 'toggle open and closed issues' },
}

--- @param t forge.Target
--- @param o forge.Open
local function open_list(t, o)
  local page = o.page or 1
  local cursors = o.cursors or {}
  local state = t.state == 'CLOSED' and 'closed' or 'open'
  local owner, repo = gh.slug(t)
  local variables = { owner = owner, repo = repo, states = t.state or 'OPEN' }
  if cursors[page] then
    variables.after = cursors[page]
  end

  gh.graphql({
    desc = ('%s issues in %s'):format(state, view.where(t)),
    query = LIST_QUERY,
    variables = variables,
    cwd = o.cwd,
  }, function(data)
    local issues = vim.tbl_get(data, 'repository', 'issues')
    local u = uri.of(vim.tbl_get(data, 'repository', 'nameWithOwner'), t)
    if not issues or not u then
      log.err(('no issues in %s'):format(view.where(t)))
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
    local pages = math.max(1, math.ceil(total / view.PER_PAGE))
    local winbar = table.concat({
      view.hl('Title', 'ISSUES'),
      view.hl('Directory', ('%s/%s'):format(view.escape(u.owner), view.escape(u.repo))),
      view.hl(STATE_HL[u.state or 'OPEN'] or '', state),
      ('%d/%d'):format(page, pages),
      view.hl('Comment', ('(%d)'):format(total)),
    }, ' ')

    view.place(o)
    local buf = view.render(u, lines, winbar, marks, LIST_MAPS)
    if info.hasNextPage and info.endCursor then
      cursors[page + 1] = info.endCursor
    end
    vim.b[buf].forge = { page = page, cursors = cursors, has_next = info.hasNextPage or false }
  end)
end

--- @param t forge.Target
--- @param o forge.Open
local function open_issue(t, o)
  local owner, repo = gh.slug(t)
  gh.graphql({
    desc = ('issue #%d in %s'):format(t.number, view.where(t)),
    query = ISSUE_QUERY,
    variables = { owner = owner, repo = repo, number = t.number },
    cwd = o.cwd,
  }, function(data)
    local issue = vim.tbl_get(data, 'repository', 'issue')
    local u = uri.of(vim.tbl_get(data, 'repository', 'nameWithOwner'), t)
    if not issue or not u then
      log.err(('no issue #%d in %s'):format(t.number, view.where(t)))
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
      ('- State: %s, opened %s'):format(issue.state or '?', text.age(issue.createdAt)),
    }
    if #labels > 0 then
      lines[#lines + 1] = ('- Labels: %s'):format(table.concat(labels, ', '))
    end
    lines[#lines + 1] = ''
    text.append_body(lines, issue.body)

    text.append_comments(lines, issue.comments)

    local winbar = table.concat({
      view.hl('Title', 'ISSUE'),
      view.hl('Tag', '#' .. issue.number),
      view.hl(STATE_HL[issue.state] or '', issue.state or '?'),
    }, ' ')

    view.place(o)
    view.render(u, lines, winbar)
    view.check_truncated(issue.comments, 'comments')
  end)
end

--- Draw the issue view `t` names.
--- @param t forge.Target
--- @param o forge.Open
function M.show(t, o)
  if t.number then
    open_issue(t, o)
  else
    open_list(t, o)
  end
end

--- Open whatever `target` names, so long as it names issues.
---
--- A bare number is taken as an issue, since github numbers issues and pull
--- requests from one counter and only github can say which it is. Anything
--- that names itself is believed, and refused here if it named the other one.
--- @param target string?
--- @param opts vim.api.keyset.create_user_command.command_args? window modifiers
function M.open(target, opts)
  view.command(target, 'issues', opts)
end

return M
