--- github, as forge.Backend asks for it: the documents it sends, the words it
--- says them in, and the addresses it builds. forge.gh underneath is the CLI
--- rather than the forge, and is shared with whatever else speaks through gh.

local gh = require('forge.gh')
local log = require('forge.log')

local M = {}

--- github numbers issues and pull requests from one counter and writes "#"
--- in front of either, which is why nothing here has to tell them apart.
--- @type table<forge.Collection, forge.Nouns>
M.nouns = {
  issues = { one = 'issue', many = 'issues', item = 'ISSUE', list = 'ISSUES', sigil = '#' },
  prs = {
    one = 'pull request',
    many = 'pull requests',
    item = 'PR',
    list = 'PRS',
    sigil = '#',
  },
}

local ISSUE_LIST = [[
query($owner: String!, $repo: String!, $after: String) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
    url
    issues(first: 100, after: $after, orderBy: {field: UPDATED_AT, direction: DESC}) {
      totalCount
      pageInfo { hasNextPage endCursor }
      nodes { number title state stateReason }
    }
  }
}
]]

local PR_LIST = [[
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

local ISSUE_ITEM = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
    issue(number: $number) {
      id number title state stateReason body createdAt url
      viewerCanUpdate
      author { login }
      authorAssociation
      labels(first: 20) { totalCount nodes { name } }
      assignees(first: 10) { totalCount nodes { login } }
      milestone { title }
      issueType { name }
      parent { number }
      comments(first: 100) {
        totalCount
        nodes { author { login } authorAssociation createdAt body }
      }
    }
  }
}
]]

local PR_ITEM = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
    url
    viewerPermission
    mergeCommitAllowed squashMergeAllowed rebaseMergeAllowed
    deleteBranchOnMerge
    pullRequest(number: $number) {
      id number title state body createdAt isDraft mergeable url
      viewerCanUpdate viewerCanMergeAsAdmin headRefOid isMergeQueueEnabled
      viewerCanEnableAutoMerge viewerCanDisableAutoMerge isInMergeQueue
      autoMergeRequest { mergeMethod }
      baseRef {
        rules(first: 50) {
          totalCount
          nodes { parameters { ... on PullRequestParameters { allowedMergeMethods } } }
        }
      }
      squashHeadline: viewerMergeHeadlineText(mergeType: SQUASH)
      squashBody: viewerMergeBodyText(mergeType: SQUASH)
      commitHeadline: viewerMergeHeadlineText(mergeType: MERGE)
      commitBody: viewerMergeBodyText(mergeType: MERGE)
      additions deletions changedFiles
      baseRefName headRefName isCrossRepository
      headRepositoryOwner { login }
      author { login }
      authorAssociation
      labels(first: 20) { totalCount nodes { name } }
      assignees(first: 10) { totalCount nodes { login } }
      milestone { title }
      reviewRequests(first: 10) {
        totalCount
        nodes { requestedReviewer { ... on User { login } ... on Team { name } } }
      }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      comments(first: 100) {
        totalCount
        nodes { author { login } authorAssociation createdAt body }
      }
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

--- One document for both collections: `type: ISSUE` searches issues and pull
--- requests alike, and which of them come back is decided by the `is:` forge
--- puts in the query. The repository is asked for alongside, since a search
--- answers for no particular one and a view still needs the name github
--- spells it with.
local SEARCH_QUERY = [[
query($owner: String!, $repo: String!, $q: String!, $after: String) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
    url
  }
  search(query: $q, type: ISSUE, first: 100, after: $after) {
    issueCount
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on Issue { number title state stateReason }
      ... on PullRequest { number title state isDraft }
    }
  }
}
]]

--- What github calls a collection in a document, in a url and in a search.
local WORDS = {
  issues = {
    list = ISSUE_LIST,
    item = ISSUE_ITEM,
    list_key = 'issues',
    item_key = 'issue',
    path = 'issues',
    kind = 'is:issue',
  },
  prs = {
    list = PR_LIST,
    item = PR_ITEM,
    list_key = 'pullRequests',
    item_key = 'pullRequest',
    path = 'pulls',
    kind = 'is:pr',
  },
}

--- Search reaches a thousand results and no further, however many it reports.
local REACHABLE = 1000

--- Qualifiers forge owns, because repeating one of these widens a search
--- rather than narrowing it: two `repo:` are two repositories, and `is:issue`
--- beside `is:pr` is both. The name a view carries would stop being true.
local OWNED = { org = true, repo = true, user = true }
local KINDS = { ['is:issue'] = true, ['is:pr'] = true, ['type:issue'] = true, ['type:pr'] = true }

--- What to send github for `query`, given what the user typed.
---
--- Their string is passed through byte for byte apart from the qualifiers
--- above, so quoting, negation and commas are github's to read rather than
--- ours to parse. Only the whole words forge owns are dropped, which leaves
--- the spaces inside a quoted value where they were.
--- @param t forge.Target
--- @return string
local function searching(t)
  local sorted = false
  local kept = (t.query or ''):gsub('%S+', function(word)
    local key = word:match('^%-?([%w-]+):')
    if key == 'sort' then
      sorted = true
    end
    if OWNED[key] or KINDS[word:lower()] then
      return ''
    end
    return nil
  end)
  local owner, repo = gh.slug(t)
  --- Ordered like the plain list unless they asked otherwise: `search` takes
  --- no orderBy, so the only way to say it is in the query, and its own
  --- default is relevance.
  local parts = { ('repo:%s/%s'):format(owner, repo), WORDS[t.collection].kind }
  if not sorted then
    parts[#parts + 1] = 'sort:updated-desc'
  end
  parts[#parts + 1] = kept
  return table.concat(parts, ' ')
end

--- @param t forge.Target
--- @param f forge.Fetch
--- @param on_done fun(page: forge.Page?)
--- @param on_fail fun()?
function M.list(t, f, on_done, on_fail)
  local words = WORDS[t.collection]
  local owner, repo = gh.slug(t)
  local q = t.query and searching(t) or nil
  local variables = { owner = owner, repo = repo }
  if q then
    variables.q = q
  end
  if f.after then
    variables.after = f.after
  end

  gh.graphql({
    desc = f.desc,
    query = q and SEARCH_QUERY or words.list,
    variables = variables,
    cwd = f.cwd,
  }, function(data)
    local conn = q and data.search or vim.tbl_get(data, 'repository', words.list_key)
    local project = vim.tbl_get(data, 'repository', 'nameWithOwner')
    if not conn or not project then
      return on_done(nil)
    end
    local info = conn.pageInfo or {}
    --- Absent where github will not count a collection past some size of it,
    --- and the count is also the only thing that says where the pages end.
    local total = conn.totalCount or conn.issueCount
    on_done({
      project = project,
      nodes = conn.nodes or {},
      total = total,
      --- A search reports every match and hands over the first thousand.
      reach = total and math.min(total, q and REACHABLE or total),
      cursor = info.hasNextPage and info.endCursor or nil,
      has_next = info.hasNextPage or false,
      url = ('%s/%s'):format(data.repository.url, words.path)
        .. (q and ('?q=' .. vim.uri_encode(q)) or ''),
    })
  end, on_fail)
end

--- @param t forge.Target
--- @param f forge.Fetch
--- @param on_done fun(one: forge.Item?)
--- @param on_fail fun()?
function M.item(t, f, on_done, on_fail)
  local words = WORDS[t.collection]
  local owner, repo = gh.slug(t)
  gh.graphql({
    desc = f.desc,
    query = words.item,
    variables = { owner = owner, repo = repo, number = t.number },
    cwd = f.cwd,
  }, function(data)
    local node = vim.tbl_get(data, 'repository', words.item_key)
    local project = vim.tbl_get(data, 'repository', 'nameWithOwner')
    if not node or not project then
      return on_done(nil)
    end
    on_done({ project = project, node = node, repo = data.repository })
  end, on_fail)
end

--- @param t forge.Target
--- @param branch string
--- @param f forge.Fetch
--- @param on_done fun(found: forge.Head)
function M.head(t, branch, f, on_done)
  local owner, repo = gh.slug(t)
  gh.graphql({
    desc = f.desc,
    query = HEAD_QUERY,
    variables = { owner = owner, repo = repo, head = branch },
    cwd = f.cwd,
  }, function(data)
    local nodes = vim.tbl_get(data, 'repository', 'pullRequests', 'nodes') or {}
    local me = vim.tbl_get(data, 'viewer', 'login')
    local mine
    for _, pull in ipairs(nodes) do
      if vim.tbl_get(pull, 'headRepositoryOwner', 'login') == me then
        mine = mine or pull
      end
    end
    local found = mine or nodes[1]
    on_done({
      project = vim.tbl_get(data, 'repository', 'nameWithOwner'),
      number = found and found.number or nil,
    })
  end)
end

--- How a closed issue ended. The reason is written into the document rather
--- than passed, because two named closings read better in a menu than one
--- closing and a second question. DUPLICATE is left out: it takes the id of
--- the issue duplicated, which is another prompt, and github asks for it the
--- same way.
local COMPLETED = [[
mutation($id: ID!) {
  closeIssue(input: {issueId: $id, stateReason: COMPLETED}) { clientMutationId }
}
]]

local NOT_PLANNED = [[
mutation($id: ID!) {
  closeIssue(input: {issueId: $id, stateReason: NOT_PLANNED}) { clientMutationId }
}
]]

local REOPEN_ISSUE = [[
mutation($id: ID!) {
  reopenIssue(input: {issueId: $id}) { clientMutationId }
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

local CLOSE_PR = [[
mutation($id: ID!) {
  closePullRequest(input: {pullRequestId: $id}) { clientMutationId }
}
]]

local REOPEN_PR = [[
mutation($id: ID!) {
  reopenPullRequest(input: {pullRequestId: $id}) { clientMutationId }
}
]]

--- `expectedHeadOid` refuses the merge if the branch moved since the view was
--- drawn, which is the one thing `gh pr merge` cannot do.
---
--- The only merge with no message; the other two are written by hand and are
--- built by `merging` below.
local REBASE = [[
mutation($id: ID!, $oid: GitObjectID!) {
  mergePullRequest(input: {pullRequestId: $id, mergeMethod: REBASE, expectedHeadOid: $oid}) {
    clientMutationId
  }
}
]]

--- A rebase writes no commit either way, so it waits without a message.
local AUTO_REBASE = [[
mutation($id: ID!, $oid: GitObjectID!) {
  enablePullRequestAutoMerge(input: {
    pullRequestId: $id
    mergeMethod: REBASE
    expectedHeadOid: $oid
  }) { clientMutationId }
}
]]

--- `disablePullRequestAutoMerge` takes only the pull request: whatever method
--- and message were waiting go with it.
local UNAUTO = [[
mutation($id: ID!) {
  disablePullRequestAutoMerge(input: {pullRequestId: $id}) { clientMutationId }
}
]]

--- A queue takes no method and no message: how it merges is the queue's own
--- setting, which is the whole point of the base branch having one.
local ENQUEUE = [[
mutation($id: ID!, $oid: GitObjectID!) {
  enqueuePullRequest(input: {pullRequestId: $id, expectedHeadOid: $oid}) {
    clientMutationId
  }
}
]]

--- `id` here is the pull request, not the entry it has in the queue, whatever
--- the name suggests.
local DEQUEUE = [[
mutation($id: ID!) {
  dequeuePullRequest(input: {id: $id}) { clientMutationId }
}
]]

--- @type table<forge.Collection, table<string, string>>
M.writes = {
  issues = {
    complete = COMPLETED,
    not_planned = NOT_PLANNED,
    reopen = REOPEN_ISSUE,
  },
  prs = {
    draft = DRAFT,
    ready = READY,
    close = CLOSE_PR,
    reopen = REOPEN_PR,
    rebase = REBASE,
    auto_rebase = AUTO_REBASE,
    unauto = UNAUTO,
    enqueue = ENQUEUE,
    dequeue = DEQUEUE,
  },
}

--- A title and a body are one write on either collection, and github spells
--- the input's key differently in each.
local EDIT = {
  issues = [[
mutation($id: ID!, $title: String!, $body: String!) {
  updateIssue(input: {id: $id, title: $title, body: $body}) { clientMutationId }
}
]],
  prs = [[
mutation($id: ID!, $title: String!, $body: String!) {
  updatePullRequest(input: {pullRequestId: $id, title: $title, body: $body}) { clientMutationId }
}
]],
}

--- `enablePullRequestAutoMerge` takes the same input as `mergePullRequest`, so
--- a merge that waits is the same document under another name.
--- @param method 'SQUASH'|'MERGE'
--- @param auto boolean whether to wait for github to say the merge may happen
--- @return string
local function merging(method, auto)
  return ([[
mutation($id: ID!, $oid: GitObjectID!, $headline: String!, $body: String!) {
  %s(input: {
    pullRequestId: $id
    mergeMethod: %s
    expectedHeadOid: $oid
    commitHeadline: $headline
    commitBody: $body
  }) { clientMutationId }
}
]]):format(auto and 'enablePullRequestAutoMerge' or 'mergePullRequest', method)
end

--- @param w forge.Write
--- @param on_done fun()
--- @param on_fail fun()?
function M.write(w, on_done, on_fail)
  local var = w.var
  local query, variables
  if w.kind == 'edit' then
    query = EDIT[w.collection]
    variables = { id = var.id, title = w.title, body = w.body }
  elseif w.kind == 'merge' then
    query = merging(w.method, w.auto == true)
    --- An empty body is sent as one. Leaving the field out has github compose
    --- the default the buffer was filled with and then discarded.
    variables = { id = var.id, oid = var.oid, headline = w.headline, body = w.body }
  else
    --- An action carries its own write, which on github is a document.
    query = w.query --[[@as string]]
    variables = { id = var.id }
    --- The head a document asks for is the one the view was drawn from, so a
    --- branch that moved since then is refused rather than merged unseen.
    if query:find('$oid', 1, true) then
      variables.oid = var.oid
    end
  end

  gh.graphql({ desc = w.desc, query = query, variables = variables, cwd = w.cwd }, on_done, on_fail)
end

--- github's own page is the form, so templates and required fields stay
--- theirs to enforce, and gh pushes the branch on the way to a pull request's.
---
--- A new issue is an address, and the view already carries the host that
--- answered for it, which is all gh would have been asked for. gh will not
--- start one without a terminal to prompt in, either. A new pull request is
--- not an address until gh has worked out what merges into what from the
--- branch you are on, and pushed it if the remote has never seen it.
--- @param t forge.Target what to add to
--- @param host string the host that answered, which on an enterprise install
--- is not the one a name defaults to
function M.create(t, host)
  if t.collection == 'issues' then
    if not host or not t.project then
      log.warn('no url for this buffer')
      return
    end
    vim.ui.open(('https://%s/%s/issues/new'):format(host, t.project))
    return
  end

  local slug = t.project
  local done = log.progress(('a new pull request in %s'):format(slug))

  vim.system({
    'gh',
    'pr',
    'create',
    '--repo',
    slug,
    '--web',
  }, { cwd = require('forge.vcs').dir(), text = true }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        local why = vim.trim((out.stderr or ''):gsub('\n.*', ''))
        why = why ~= '' and why or 'gh pr create failed'
        done('failed', why)
        return log.err(why)
      end
      done('success', ('a new pull request in %s'):format(slug))
    end)
  end)
end

--- Where github publishes a pull request's head.
---
--- Every one of them is served as `refs/pull/N/head` on the base repository,
--- so a pull request nobody has fetched is still one fetch away.
--- @param number integer
--- @return string
function M.pull_ref(number)
  return ('refs/pull/%d/head'):format(number)
end

return M
