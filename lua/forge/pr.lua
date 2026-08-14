local gh = require('forge.gh')
local log = require('forge.log')
local text = require('forge.text')
local view = require('forge.view')

local M = {}

local LIST_QUERY = [[
query($owner: String!, $repo: String!, $states: [PullRequestState!], $after: String) {
  repository(owner: $owner, name: $repo) {
    pullRequests(
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

local PR_QUERY = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      number title state body createdAt isDraft
      additions deletions changedFiles
      baseRefName headRefName
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

--- A draft is OPEN with a flag, so it is resolved before this is consulted.
local STATE_HL = { OPEN = 'OkMsg', CLOSED = 'ErrorMsg', MERGED = 'Special', DRAFT = '' }

--- A closed pull request is either closed or merged, which is the split
--- github's own Closed tab makes.
local STATES = { OPEN = 'OPEN', CLOSED = { 'CLOSED', 'MERGED' } }

local LIST_MAPS = {
  { '<CR>', '<Plug>(forge-open)', 'open the pull request under the cursor' },
  { 'o', '<Plug>(forge-open-split)', 'open the pull request under the cursor in a split' },
  { ']p', '<Plug>(forge-next-page)', 'the next page of pull requests' },
  { '[p', '<Plug>(forge-prev-page)', 'the previous page of pull requests' },
  { 'g.', '<Plug>(forge-state)', 'toggle open and closed pull requests' },
}

--- @param u forge.Uri
--- @param page integer
--- @param cursors table<integer, string>
local function open_list(u, page, cursors)
  local state = u.state == 'CLOSED' and 'closed' or 'open'
  local variables = { owner = u.owner, repo = u.repo, states = STATES[u.state or 'OPEN'] }
  if cursors[page] then
    variables.after = cursors[page]
  end

  gh.graphql(
    ('%s/%s %s pull requests'):format(u.owner, u.repo, state),
    LIST_QUERY,
    variables,
    function(data)
      local prs = vim.tbl_get(data, 'repository', 'pullRequests')
      if not prs then
        log.err(('no such repository: %s/%s'):format(u.owner, u.repo))
        return
      end

      local nodes = prs.nodes or {}
      local width = 1
      for _, pr in ipairs(nodes) do
        width = math.max(width, #tostring(pr.number))
      end
      local format = ('#%%-%dd %%s'):format(width)

      local lines, marks = {}, {}
      for _, pr in ipairs(nodes) do
        local row = #lines
        lines[row + 1] = format:format(pr.number, pr.title)
        marks[#marks + 1] =
          { row = row, col = 0, end_col = 1 + #tostring(pr.number), group = 'Tag' }
      end
      if #lines == 0 then
        lines = { ('No %s pull requests.'):format(state) }
        marks = { { row = 0, col = 0, end_col = #lines[1], group = 'Comment' } }
      end

      local info = prs.pageInfo or {}
      local total = prs.totalCount or #lines
      local pages = math.max(1, math.ceil(total / view.PER_PAGE))
      local winbar = table.concat({
        view.hl('Title', 'PRS'),
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
local function open_pr(u)
  gh.graphql(
    ('%s/%s#%d'):format(u.owner, u.repo, u.number),
    PR_QUERY,
    { owner = u.owner, repo = u.repo, number = u.number },
    function(data)
      local pr = vim.tbl_get(data, 'repository', 'pullRequest')
      if not pr then
        log.err(('no such pull request: %s/%s#%d'):format(u.owner, u.repo, u.number))
        return
      end

      local state = pr.isDraft and 'DRAFT' or (pr.state or '?')
      local labels = {}
      for _, label in ipairs(vim.tbl_get(pr, 'labels', 'nodes') or {}) do
        labels[#labels + 1] = label.name
      end

      local lines = {
        ('# %s'):format(pr.title),
        '',
        ('- Author: %s (%s)'):format(
          vim.tbl_get(pr, 'author', 'login') or 'ghost',
          pr.authorAssociation or 'NONE'
        ),
        ('- State: %s, opened %s'):format(state, text.age(pr.createdAt)),
        ('- Branch: %s into %s'):format(pr.headRefName or '?', pr.baseRefName or '?'),
      }
      if #labels > 0 then
        lines[#lines + 1] = ('- Labels: %s'):format(table.concat(labels, ', '))
      end
      lines[#lines + 1] = ''
      text.append_body(lines, pr.body)
      text.append_comments(lines, pr.comments)

      local winbar = table.concat({
        view.hl('Title', 'PR'),
        view.hl('Tag', '#' .. pr.number),
        view.hl(STATE_HL[state] or '', state),
        view.hl('Added', ('+%d'):format(pr.additions or 0)),
        view.hl('Removed', ('-%d'):format(pr.deletions or 0)),
      }, ' ')

      view.render(u, lines, winbar)
      view.check_truncated(pr.comments, 'comments')
    end
  )
end

--- Draw the pull request view `u` names.
--- @param u forge.Uri
--- @param page integer
--- @param cursors table<integer, string>
function M.show(u, page, cursors)
  if u.number then
    open_pr(u)
  else
    open_list(u, page, cursors)
  end
end

--- Open whatever `target` names, so long as it names pull requests.
---
--- A bare number is taken as a pull request, since github numbers issues and
--- pull requests from one counter and only github can say which it is.
--- Anything that names itself is believed, and refused here if it named the
--- other one.
--- @param target string?
function M.open(target)
  local u, err = require('forge.uri').resolve(target, 'pulls')
  if not u then
    log.err(err or 'cannot resolve target')
    return
  end
  if u.collection ~= 'pulls' then
    log.err('that names issues; use :Issue')
    return
  end
  M.show(u, 1, {})
end

return M
