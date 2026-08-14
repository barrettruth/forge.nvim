local gh = require('forge.gh')
local log = require('forge.log')
local text = require('forge.text')
local view = require('forge.view')

local M = {}

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

local STATE_HL = { OPEN = 'OkMsg', CLOSED = 'ErrorMsg' }

local LIST_MAPS = {
  { '<CR>', '<Plug>(forge-open)', 'open the issue under the cursor' },
  { 'o', '<Plug>(forge-open-split)', 'open the issue under the cursor in a split' },
  { ']i', '<Plug>(forge-next-page)', 'the next page of issues' },
  { '[i', '<Plug>(forge-prev-page)', 'the previous page of issues' },
  { 'g.', '<Plug>(forge-state)', 'toggle open and closed issues' },
}

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
      local pages = math.max(1, math.ceil(total / view.PER_PAGE))
      local winbar = table.concat({
        view.hl('Title', 'ISSUES'),
        view.hl('Directory', ('%s/%s'):format(view.escape(u.owner), view.escape(u.repo))),
        view.hl(STATE_HL[u.state or 'OPEN'] or '', state),
        ('%d/%d'):format(page, pages),
        view.hl('Comment', ('(%d)'):format(total)),
      }, ' ')

      local buf = view.render(u, lines, winbar, marks, LIST_MAPS)
      if info.hasNextPage and info.endCursor then
        cursors[page + 1] = info.endCursor
      end
      vim.b[buf].forge = { page = page, cursors = cursors, has_next = info.hasNextPage or false }
    end
  )
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

      view.render(u, lines, winbar)
      view.check_truncated(issue.comments, 'comments')
    end
  )
end

--- Draw the issue view `u` names.
--- @param u forge.Uri
--- @param page integer
--- @param cursors table<integer, string>
function M.show(u, page, cursors)
  if u.number then
    open_issue(u)
  else
    open_list(u, page, cursors)
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
  local u, err = require('forge.uri').resolve(target, 'issues')
  if not u then
    log.err(err or 'cannot resolve target')
    return
  end
  if u.collection ~= 'issues' then
    log.err('that names pull requests; use :PR')
    return
  end
  view.split_for(opts)
  M.show(u, 1, {})
end

return M
