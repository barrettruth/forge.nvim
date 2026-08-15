local collection = require('forge.collection')
local gh = require('forge.gh')
local log = require('forge.log')
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

--- @type forge.Spec
local PRS = {
  one = 'pull request',
  many = 'pull requests',
  item_title = 'PR',
  list_title = 'PRS',
  item_key = 'pullRequest',
  list_key = 'pullRequests',
  item_query = PR_QUERY,
  list_query = LIST_QUERY,
  --- A closed pull request is either closed or merged, which is the split
  --- github's own Closed tab makes.
  states = { OPEN = 'OPEN', CLOSED = { 'CLOSED', 'MERGED' } },
  --- A draft is OPEN with a flag, so it is resolved before this is consulted.
  state_hl = { OPEN = 'OkMsg', CLOSED = 'ErrorMsg', MERGED = 'Special', DRAFT = '' },
  list_maps = {
    { '<CR>', '<Plug>(forge-open)', 'open the pull request under the cursor' },
    { 'o', '<Plug>(forge-open-split)', 'open the pull request under the cursor in a split' },
    { ']p', '<Plug>(forge-next-page)', 'the next page of pull requests' },
    { '[p', '<Plug>(forge-prev-page)', 'the previous page of pull requests' },
    { 'g.', '<Plug>(forge-state)', 'toggle open and closed pull requests' },
  },
  --- A pull request is the only view with checks behind it, so "dc" is bound
  --- here rather than everywhere. An issue has no CI, and a key that exists
  --- only to refuse is worse than no key.
  item_maps = {
    { 'dc', '<Plug>(forge-checks)', "show this pull request's checks in ci.nvim" },
  },
  state = function(node)
    return node.isDraft and 'DRAFT' or node.state
  end,
  header = function(node)
    return { ('- Branch: %s into %s'):format(node.headRefName or '?', node.baseRefName or '?') }
  end,
  badges = function(node)
    return {
      view.hl('Added', ('+%d'):format(node.additions or 0)),
      view.hl('Removed', ('-%d'):format(node.deletions or 0)),
    }
  end,
}

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
    collection.item(PRS, uri.of(slug, item) or item, o)
  end)
end

--- Draw the pull request view `t` names.
--- @param t forge.Target
--- @param o forge.Open
function M.show(t, o)
  if t.head then
    open_head(t, o)
  elseif t.number then
    collection.item(PRS, t, o)
  else
    collection.list(PRS, t, o)
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
