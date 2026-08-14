local gh = require('forge.gh')
local log = require('forge.log')
local text = require('forge.text')
local uri = require('forge.uri')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

local LIST_QUERY = [[
query($owner: String!, $repo: String!, $states: [PullRequestState!], $after: String) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
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

--- The open pull request whose head is a given branch.
---
--- A fork's pull request lives on the base repository, where a branch name is
--- not necessarily unique, so the viewer's own is preferred over a stranger's
--- that happens to share it.
local HEAD_QUERY = [[
query($owner: String!, $repo: String!, $head: String!) {
  viewer { login }
  repository(owner: $owner, name: $repo) {
    nameWithOwner
    pullRequests(
      headRefName: $head
      states: [OPEN]
      first: 10
      orderBy: {field: UPDATED_AT, direction: DESC}
    ) {
      nodes { number headRepositoryOwner { login } }
    }
  }
}
]]

local PR_QUERY = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
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

--- @param t forge.Target
--- @param o forge.Open
local function open_list(t, o)
  local page = o.page or 1
  local cursors = o.cursors or {}
  local state = t.state == 'CLOSED' and 'closed' or 'open'
  local owner, repo = gh.slug(t)
  local variables = { owner = owner, repo = repo, states = STATES[t.state or 'OPEN'] }
  if cursors[view.at(page)] then
    variables.after = cursors[view.at(page)]
  end

  gh.graphql({
    desc = ('%s pull requests in %s'):format(state, view.where(t)),
    query = LIST_QUERY,
    variables = variables,
    cwd = o.cwd,
  }, function(data)
    local prs = vim.tbl_get(data, 'repository', 'pullRequests')
    local u = uri.of(vim.tbl_get(data, 'repository', 'nameWithOwner'), t)
    if not prs or not u then
      log.err(('no pull requests in %s'):format(view.where(t)))
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
      marks[#marks + 1] = { row = row, col = 0, end_col = 1 + #tostring(pr.number), group = 'Tag' }
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

    view.place(o)
    local buf = view.render(u, lines, winbar, marks, LIST_MAPS)
    if info.hasNextPage and info.endCursor then
      cursors[view.at(page + 1)] = info.endCursor
    end
    vim.b[buf].forge = { page = page, cursors = cursors, has_next = info.hasNextPage or false }
  end)
end

--- @param t forge.Target
--- @param o forge.Open
local function open_pr(t, o)
  local owner, repo = gh.slug(t)
  gh.graphql({
    desc = ('pull request #%d in %s'):format(t.number, view.where(t)),
    query = PR_QUERY,
    variables = { owner = owner, repo = repo, number = t.number },
    cwd = o.cwd,
  }, function(data)
    local pr = vim.tbl_get(data, 'repository', 'pullRequest')
    local u = uri.of(vim.tbl_get(data, 'repository', 'nameWithOwner'), t)
    if not pr or not u then
      log.err(('no pull request #%d in %s'):format(t.number, view.where(t)))
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

    view.place(o)
    view.render(u, lines, winbar)
    view.check_truncated(pr.comments, 'comments')
  end)
end

--- Open the pull request for the branch checked out here.
---
--- The branch is found locally and the pull request is asked for by name, so a
--- fork is answered by the repository the pull request is actually on.
--- @param t forge.Target
--- @param o forge.Open
local function open_head(t, o)
  local branch, err = vcs.branch(o.cwd or vim.fn.getcwd())
  if not branch then
    log.err(err or 'cannot tell which branch this is')
    return
  end

  local owner, repo = gh.slug(t)
  gh.graphql({
    desc = ('the pull request for %s'):format(branch),
    query = HEAD_QUERY,
    variables = { owner = owner, repo = repo, head = branch },
    cwd = o.cwd,
  }, function(data)
    local slug = vim.tbl_get(data, 'repository', 'nameWithOwner')
    local nodes = vim.tbl_get(data, 'repository', 'pullRequests', 'nodes') or {}
    local me = vim.tbl_get(data, 'viewer', 'login')
    local mine
    for _, pr in ipairs(nodes) do
      if vim.tbl_get(pr, 'headRepositoryOwner', 'login') == me then
        mine = mine or pr
      end
    end
    local found = mine or nodes[1]
    if not found then
      log.err(('no open pull request for %s'):format(branch))
      return
    end
    local item = { collection = 'prs', number = found.number }
    open_pr(uri.of(slug, item) or item, o)
  end)
end

--- Draw the pull request view `t` names.
--- @param t forge.Target
--- @param o forge.Open
function M.show(t, o)
  if t.head then
    open_head(t, o)
  elseif t.number then
    open_pr(t, o)
  else
    open_list(t, o)
  end
end

--- Open whatever `target` names, so long as it names pull requests.
---
--- A bare number is taken as a pull request, since github numbers issues and
--- pull requests from one counter and only github can say which it is.
--- Anything that names itself is believed, and refused here if it named the
--- other one.
--- @param target string?
--- @param opts vim.api.keyset.create_user_command.command_args? window modifiers
function M.open(target, opts)
  view.command(target, 'prs', opts)
end

return M
