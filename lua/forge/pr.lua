local collection = require('forge.collection')
local gh = require('forge.gh')
local log = require('forge.log')
local uri = require('forge.uri')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

local LIST_QUERY = [[
query($owner: String!, $repo: String!, $after: String) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
    url
    pullRequests(first: 100, after: $after, orderBy: {field: UPDATED_AT, direction: DESC}) {
      totalCount
      pageInfo { hasNextPage endCursor }
      nodes { number title state isDraft }
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
    url
    viewerPermission
    mergeCommitAllowed squashMergeAllowed rebaseMergeAllowed
    pullRequest(number: $number) {
      id number title state body createdAt isDraft mergeable url
      viewerCanUpdate headRefOid isMergeQueueEnabled
      baseRef {
        rules(first: 50) {
          totalCount
          nodes { parameters { ... on PullRequestParameters { allowedMergeMethods } } }
        }
      }
      additions deletions changedFiles
      baseRefName headRefName
      author { login }
      authorAssociation
      labels(first: 20) { totalCount nodes { name } }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      comments(first: 100) {
        totalCount
        nodes { author { login } authorAssociation createdAt body }
      }
    }
  }
}
]]

local DRAFT = [[
mutation($id: ID!) {
  convertPullRequestToDraft(input: {pullRequestId: $id}) { clientMutationId }
}
]]

local READY = [[
mutation($id: ID!) {
  markPullRequestReadyForReview(input: {pullRequestId: $id}) { clientMutationId }
}
]]

local CLOSE = [[
mutation($id: ID!) {
  closePullRequest(input: {pullRequestId: $id}) { clientMutationId }
}
]]

local REOPEN = [[
mutation($id: ID!) {
  reopenPullRequest(input: {pullRequestId: $id}) { clientMutationId }
}
]]

--- `expectedHeadOid` refuses the merge if the branch moved since the view was
--- drawn, which is the one thing `gh pr merge` cannot do.
local function merging(method)
  return ([[
mutation($id: ID!, $oid: GitObjectID!) {
  mergePullRequest(input: {pullRequestId: $id, mergeMethod: %s, expectedHeadOid: $oid}) {
    clientMutationId
  }
}
]]):format(method)
end

local SQUASH, COMMIT, REBASE = merging('SQUASH'), merging('MERGE'), merging('REBASE')

local WRITES = { WRITE = true, MAINTAIN = true, ADMIN = true }

--- Which merge methods github would accept on this pull request, now.
---
--- Three things have to agree, and there is no single field for it: there is no
--- `viewerCanMerge`. `viewerCanUpdate` cannot stand in, because an author with
--- no write access has it — that is how you end up offering to merge a stranger's
--- repository. `viewerCanMergeAsAdmin` is about bypassing protection and is false
--- for an admin with nothing to bypass. So write access comes from the
--- repository, the methods from its switches narrowed by whatever ruleset governs
--- the base, and `mergeStateStatus` is left out of it entirely: github computes it
--- lazily and answers UNKNOWN on a pull request it has not looked at lately, which
--- would hide the action rather than explain it.
---
--- A ruleset too long for one page is ignored rather than guessed at. github
--- refuses the merge either way and names the reason.
--- @param node table
--- @param repo table
--- @return table<string, boolean>
local function merges(node, repo)
  local ok = {}
  if
    not WRITES[repo.viewerPermission]
    or node.isMergeQueueEnabled
    or node.mergeable == 'CONFLICTING'
  then
    return ok
  end
  ok.MERGE = repo.mergeCommitAllowed == true
  ok.SQUASH = repo.squashMergeAllowed == true
  ok.REBASE = repo.rebaseMergeAllowed == true

  local rules = vim.tbl_get(node, 'baseRef', 'rules') or {}
  local nodes = rules.nodes or {}
  if (rules.totalCount or 0) > #nodes then
    return ok
  end
  for _, rule in ipairs(nodes) do
    local allowed = vim.tbl_get(rule, 'parameters', 'allowedMergeMethods')
    if allowed then
      for method in pairs(ok) do
        ok[method] = ok[method] and vim.tbl_contains(allowed, method)
      end
    end
  end
  return ok
end

--- What a rollup state is worth saying, and how. A repository with no checks
--- has no rollup at all, and one that passed has nothing to report.
local CHECKS = {
  ERROR = { 'FAILING', view.HL.bad },
  FAILURE = { 'FAILING', view.HL.bad },
  PENDING = { 'PENDING', view.HL.waiting },
  EXPECTED = { 'EXPECTED', view.HL.waiting },
}

--- @param node table
--- @return string? state of the head commit's checks, if it has any
local function rollup(node)
  local commits = vim.tbl_get(node, 'commits', 'nodes') or {}
  return vim.tbl_get(commits[1] or {}, 'commit', 'statusCheckRollup', 'state')
end

--- @type forge.Spec
local PRS = {
  one = 'pull request',
  many = 'pull requests',
  item_title = 'PR',
  list_title = 'PRS',
  item_key = 'pullRequest',
  list_key = 'pullRequests',
  list_path = 'pulls',
  kind = 'is:pr',
  item_query = PR_QUERY,
  list_query = LIST_QUERY,
  --- A draft is OPEN with a flag, so it is resolved before this is consulted.
  state_hl = {
    OPEN = view.HL.live,
    CLOSED = view.HL.bad,
    MERGED = view.HL.done,
    DRAFT = view.HL.inert,
  },
  list_maps = {
    { '<CR>', '<Plug>(forge-open)', 'open the pull request under the cursor' },
    { 'o', '<Plug>(forge-open-split)', 'open the pull request under the cursor in a split' },
    { ']p', '<Plug>(forge-next-page)', 'the next page of pull requests' },
    { '[p', '<Plug>(forge-prev-page)', 'the previous page of pull requests' },
  },
  --- A pull request is the only view with checks behind it, so "dc" is bound
  --- here rather than everywhere. An issue has no CI, and a key that exists
  --- only to refuse is worse than no key.
  item_maps = {
    { 'cc', '<Plug>(forge-act)', 'do something to this pull request' },
    { 'dc', '<Plug>(forge-checks)', "show this pull request's checks in ci.nvim" },
    { 'dd', '<Plug>(forge-diff)', "show this pull request's diff in diffs.nvim" },
    { 'dl', '<Plug>(forge-log)', "show this pull request's commits in fugitive" },
  },
  --- Which branches it joins cannot be read back off the view, and "dd" needs
  --- them to ask diffs.nvim for the right merge base. The repository github
  --- named is what "dd" and "dl" fetch from, so it comes too.
  remember = function(node, repo)
    local ok = merges(node, repo)
    return {
      id = node.id,
      can_update = node.viewerCanUpdate,
      oid = node.headRefOid,
      can_squash = ok.SQUASH == true,
      can_merge_commit = ok.MERGE == true,
      can_rebase = ok.REBASE == true,
      base = node.baseRefName,
      head = node.headRefName,
      remote = repo.url,
    }
  end,
  --- Draft is a flag on an open pull request, and github leaves it set when
  --- one is closed; a closed draft is closed.
  state = function(node)
    return (node.state == 'OPEN' and node.isDraft) and 'DRAFT' or node.state
  end,
  header = function(node)
    return { ('- Branch: %s into %s'):format(node.headRefName or '?', node.baseRefName or '?') }
  end,
  --- Of `mergeStateStatus`'s seven values only DIRTY is actionable, and this
  --- is it, so that enum is left unasked for.
  badges = function(node)
    local badges = {}
    if node.mergeable == 'CONFLICTING' then
      badges[#badges + 1] = view.hl(view.HL.bad, 'CONFLICT')
    end
    local checks = CHECKS[rollup(node) or '']
    if checks then
      badges[#badges + 1] = view.hl(checks[2], checks[1])
    end
    return badges
  end,
  stat = function(node)
    return {
      view.hl('Added', ('+%d'):format(node.additions or 0)),
      view.hl('Removed', ('-%d'):format(node.deletions or 0)),
    }
  end,
  --- Closing comes after the reversible one, so a mistyped pick is the harmless
  --- one. `viewerCanReopen` is deliberately not asked for: it is false once the
  --- head branch is gone, but an empty menu cannot say that, and github's own
  --- refusal names the branch.
  actions = {
    {
      label = 'Edit title and body',
      when = function(var)
        return var.can_update == true
      end,
      run = function(var)
        require('forge.edit').open(var)
      end,
    },
    {
      label = 'Convert to draft',
      query = DRAFT,
      when = function(var)
        return var.state == 'OPEN' and var.can_update == true
      end,
    },
    {
      label = 'Ready for review',
      query = READY,
      when = function(var)
        return var.state == 'DRAFT' and var.can_update == true
      end,
    },
    {
      label = 'Close pull request',
      query = CLOSE,
      when = function(var)
        return (var.state == 'OPEN' or var.state == 'DRAFT') and var.can_update == true
      end,
    },
    {
      label = 'Reopen pull request',
      query = REOPEN,
      when = function(var)
        return var.state == 'CLOSED' and var.can_update == true
      end,
    },
    --- Last, and each already weighed by `merges`: what is left to ask here is
    --- only whether the pull request is open, since a draft cannot be merged
    --- and DRAFT is resolved before any of this is read.
    {
      label = 'Squash and merge',
      query = SQUASH,
      when = function(var)
        return var.state == 'OPEN' and var.can_squash == true
      end,
    },
    {
      label = 'Create a merge commit',
      query = COMMIT,
      when = function(var)
        return var.state == 'OPEN' and var.can_merge_commit == true
      end,
    },
    {
      label = 'Rebase and merge',
      query = REBASE,
      when = function(var)
        return var.state == 'OPEN' and var.can_rebase == true
      end,
    },
  },
}

--- What this pull request can be asked to do, as it stands.
--- @param var forge.ItemVar
--- @return forge.Action[]
function M.actions(var)
  return collection.actions(PRS, var)
end

--- Offer those, and do the one chosen.
function M.act()
  collection.act(PRS)
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
      log.info(('no pull request for %s yet, so opening a new one'):format(branch))
      view.create(uri.of(slug, { collection = 'prs' }))
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
--- A bare number is taken as a pull request: github numbers both from one
--- counter, so only github can say which it is.
--- @param target string?
--- @param opts vim.api.keyset.create_user_command.command_args? window modifiers
function M.open(target, opts)
  view.command(target, 'prs', opts)
end

return M
