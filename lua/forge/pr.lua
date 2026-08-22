local backend = require('forge.backend')
local collection = require('forge.collection')
local log = require('forge.log')
local text = require('forge.text')
local uri = require('forge.uri')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

--- @param method 'SQUASH'|'MERGE'
--- @param auto boolean
--- @return fun(var: forge.ItemVar)
local function writing(method, auto)
  return function(var)
    require('forge.merge').open(var, method, auto)
  end
end

local squashing, committing = writing('SQUASH', false), writing('MERGE', false)
local auto_squashing, auto_committing = writing('SQUASH', true), writing('MERGE', true)

local WRITES = { WRITE = true, MAINTAIN = true, ADMIN = true }

--- Whether a merge of any name may be offered on this one.
---
--- A stack the forge keeps of its own merges as a unit, and none of the
--- labels below says so: merging a layer takes every layer under it along.
--- github refuses both documents outright, naming its asynchronous REST
--- endpoint in place of `mergePullRequest` and nothing at all in place of
--- `enablePullRequestAutoMerge`. A chain forge derived is no such thing and
--- merges a layer at a time, as any pull request does.
--- @param var forge.ItemVar
--- @return boolean
local function may_merge(var)
  return var.state == 'OPEN' and var.stack_kept ~= true
end

--- When to offer one of the two names a merge has.
---
--- Both send the same document. `mergePullRequest` has no bypass field. The
--- choice here is only what to call it. `viewerCanMergeAsAdmin` is false for
--- an admin with nothing to bypass, and the pair is never offered together.
--- @param can string the field saying github would take this method at all
--- @param bypass boolean which of the pair this is
--- @return fun(var: forge.ItemVar): boolean
local function naming(can, bypass)
  return function(var)
    return may_merge(var) and var[can] == true and (var.can_bypass == true) == bypass
  end
end

--- When to offer a merge that waits for github to allow it.
---
--- `viewerCanEnableAutoMerge` covers the repository's switch and your access.
--- It is false on a pull request that could merge now. The method is still
--- checked here. github checks it when the wait ends, not when it starts.
--- @param can string
--- @return fun(var: forge.ItemVar): boolean
local function waiting(can)
  return function(var)
    return may_merge(var) and var[can] == true and var.can_auto == true and var.auto == nil
  end
end

--- Which merge methods github would accept on this pull request, now.
---
--- There is no `viewerCanMerge`. This is assembled: write access from the
--- repository, the methods from its switches narrowed by the base branch's
--- ruleset. `viewerCanUpdate` cannot stand in. An author with no write access
--- has it. `mergeStateStatus` is left out. github computes it lazily and
--- answers UNKNOWN on a pull request it has not looked at lately.
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
  -- A ruleset too long for one page is left unnarrowed, not guessed at.
  -- github refuses the merge either way, and names the reason.
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

--- The rollup states worth a badge. A repository with no checks has no rollup,
--- and one that passed has nothing to report.
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
  collection = 'prs',
  -- A draft is OPEN with a flag, and `state` below resolves it first.
  state_hl = {
    OPEN = view.HL.live,
    CLOSED = view.HL.bad,
    MERGED = view.HL.done,
    DRAFT = view.HL.inert,
  },
  list_maps = {
    { '<CR>', '<Plug>(forge-open)', 'open the {one} under the cursor' },
    { 'o', '<Plug>(forge-open-split)', 'open the {one} under the cursor in a split' },
    { ']p', '<Plug>(forge-next-page)', 'the next page of {many}' },
    { '[p', '<Plug>(forge-prev-page)', 'the previous page of {many}' },
  },
  -- An issue has no CI, no diff, no commits and no stack. These are bound here
  -- rather than in every item. A key that exists only to refuse is worse.
  item_maps = {
    { '<CR>', '<Plug>(forge-open)', 'open the {one} the line names' },
    { 'cc', '<Plug>(forge-act)', 'do something to this {one}' },
    { 'cE', '<Plug>(forge-edit)', "edit this {one}'s title and body" },
    { 'cD', '<Plug>(forge-draft)', 'draft this {one}, or mark it ready' },
    { 'cS', '<Plug>(forge-squash)', 'squash and merge this {one}' },
    { 'cM', '<Plug>(forge-merge)', 'merge this {one} with a merge commit' },
    { 'dc', '<Plug>(forge-checks)', "show this {one}'s checks in ci.nvim" },
    { 'dd', '<Plug>(forge-diff)', "show this {one}'s diff in diffs.nvim" },
    { 'dl', '<Plug>(forge-log)', "show this {one}'s commits in fugitive" },
    { '[s', '<Plug>(forge-stack-up)', 'the {one} above this one in its stack' },
    { ']s', '<Plug>(forge-stack-down)', 'the {one} below this one in its stack' },
    { ']p', '<Plug>(forge-next-item)', 'the next {one} in the list this came from' },
    { '[p', '<Plug>(forge-prev-item)', 'the previous {one} in the list this came from' },
  },
  stacked = true,
  -- The branches and the repository cannot be read back off a drawn view.
  -- "dd" and "dl" need both to fetch and to find the merge base.
  remember = function(node, repo)
    local ok = merges(node, repo)
    return {
      id = node.id,
      can_update = node.viewerCanUpdate,
      oid = node.headRefOid,
      can_squash = ok.SQUASH == true,
      can_merge_commit = ok.MERGE == true,
      can_rebase = ok.REBASE == true,
      can_bypass = node.viewerCanMergeAsAdmin == true,
      -- github only offers auto-merge where it will not merge now. This is
      -- true in much the same places `can_bypass` is.
      can_auto = node.viewerCanEnableAutoMerge == true,
      can_unauto = node.viewerCanDisableAutoMerge == true,
      -- A base branch with a queue refuses every direct merge. `merges` offers
      -- none, and the queue is the only way in.
      queued = node.isMergeQueueEnabled == true,
      in_queue = node.isInMergeQueue == true,
      auto = vim.tbl_get(node, 'autoMergeRequest', 'mergeMethod'),
      -- The message github itself would write, honouring the repository's own
      -- commit title and body settings. Rebase is asked for neither. github
      -- answers "" for both. There is no message to write.
      merge = {
        SQUASH = { headline = node.squashHeadline or '', body = node.squashBody or '' },
        MERGE = { headline = node.commitHeadline or '', body = node.commitBody or '' },
      },
      base = node.baseRefName,
      -- A branch name alone does not say it came from a fork.
      head = node.isCrossRepository and ('%s:%s'):format(
        vim.tbl_get(node, 'headRepositoryOwner', 'login') or '?',
        node.headRefName or '?'
      ) or node.headRefName,
      remote = repo.url,
    }
  end,
  -- github leaves isDraft set on a closed pull request. A closed draft is
  -- closed.
  state = function(node)
    return (node.state == 'OPEN' and node.isDraft) and 'DRAFT' or node.state
  end,
  -- The branches take the room a title would. The winbar draws them from
  -- |b:forge| itself.
  about = function()
    return ''
  end,
  -- Only the outstanding reviewers: github drops a request once its reviewer
  -- answers.
  rows = function(node)
    local asked = {}
    for _, request in ipairs(vim.tbl_get(node, 'reviewRequests', 'nodes') or {}) do
      asked[#asked + 1] = request.requestedReviewer
    end
    return {
      { key = 'Reviewers', values = text.logins({ nodes = asked }), group = text.LOGIN },
    }
  end,
  -- `mergeable` rather than `mergeStateStatus`. Of that enum's seven values
  -- only DIRTY is actionable, and this is it.
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
  -- Ordered so that a mistyped pick lands on the reversible neighbour.
  -- `viewerCanReopen` is not asked for. It is false once the head branch is
  -- gone. An empty menu cannot say that. github's refusal names it.
  actions = {
    {
      label = 'Edit title and body',
      key = 'edit',
      when = function(var)
        return var.can_update == true
      end,
      run = function(var)
        require('forge.edit').open(var)
      end,
    },
    -- One key for the pair: the state tells them apart, so only ever one of
    -- them is offered, and the winbar says which.
    {
      label = 'Convert to draft',
      key = 'draft',
      write = 'draft',
      when = function(var)
        return var.state == 'OPEN' and var.can_update == true
      end,
    },
    {
      label = 'Ready for review',
      key = 'draft',
      write = 'ready',
      when = function(var)
        return var.state == 'DRAFT' and var.can_update == true
      end,
    },
    {
      label = 'Close {one}',
      write = 'close',
      when = function(var)
        return (var.state == 'OPEN' or var.state == 'DRAFT') and var.can_update == true
      end,
    },
    {
      label = 'Reopen {one}',
      write = 'reopen',
      when = function(var)
        return var.state == 'CLOSED' and var.can_update == true
      end,
    },
    -- Everything below is already weighed by `merges`. OPEN is all these have
    -- left to test. A queue merges when it gets there. Joining and leaving one
    -- stand where the merges would.
    {
      label = 'Add to merge queue',
      write = 'enqueue',
      when = function(var)
        return var.state == 'OPEN' and var.queued == true and var.in_queue ~= true
      end,
    },
    {
      label = 'Remove from merge queue',
      write = 'dequeue',
      when = function(var)
        return var.in_queue == true
      end,
    },
    -- Waiting comes before merging. A merge that waits can be called off. One
    -- that happens cannot.
    {
      label = 'Enable auto-merge (squash)',
      run = auto_squashing,
      when = waiting('can_squash'),
    },
    {
      label = 'Enable auto-merge (merge commit)',
      run = auto_committing,
      when = waiting('can_merge_commit'),
    },
    {
      label = 'Enable auto-merge (rebase)',
      write = 'auto_rebase',
      when = waiting('can_rebase'),
    },
    {
      label = 'Disable auto-merge',
      write = 'unauto',
      when = function(var)
        return var.auto ~= nil and var.can_unauto == true
      end,
    },
    -- The two that write a commit open a buffer for its message. A rebase
    -- writes none and goes straight out.
    {
      label = 'Squash and merge',
      key = 'squash',
      run = squashing,
      when = naming('can_squash', false),
    },
    {
      label = 'Squash and merge (bypass)',
      key = 'squash',
      run = squashing,
      when = naming('can_squash', true),
    },
    {
      label = 'Create a merge commit',
      key = 'commit',
      run = committing,
      when = naming('can_merge_commit', false),
    },
    {
      label = 'Create a merge commit (bypass)',
      key = 'commit',
      run = committing,
      when = naming('can_merge_commit', true),
    },
    { label = 'Rebase and merge', write = 'rebase', when = naming('can_rebase', false) },
    { label = 'Rebase and merge (bypass)', write = 'rebase', when = naming('can_rebase', true) },
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

--- Do the one thing `key` names, if it is offered.
--- @param key string
function M.one(key)
  collection.one(PRS, key)
end

--- Open the pull request for the branch checked out here.
---
--- The branch is found locally. The pull request is asked for by name, which
--- answers a fork from the repository the pull request is actually on.
--- @param t forge.Target
--- @param o forge.Open
local function open_head(t, o)
  local be, host = backend.of(t.host, o.cwd)
  t = vim.tbl_extend('keep', t, { host = host })
  if not be then
    return
  end
  local branch, err = vcs.branch(o.cwd or vim.fn.getcwd())
  if not branch then
    log.err(err or 'cannot tell which branch this is')
    return
  end

  local nouns = be.nouns.prs
  be.head(t, branch, {
    desc = ('the %s for %s'):format(nouns.one, branch),
    cwd = o.cwd,
  }, function(found)
    if not found.number then
      log.info(('no %s for %s yet, so opening a new one'):format(nouns.one, branch))
      view.create(uri.of(found.project, { host = t.host, collection = 'prs' }))
      return
    end
    -- The host is carried over from `t`. Whatever answered for the branch is
    -- what to ask about the change on it.
    local item = { host = t.host, collection = 'prs', number = found.number }
    collection.item(PRS, uri.of(found.project, item) or item, o)
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

--- Open whatever `target` names, so long as it names pull requests. A bare
--- number is one: github numbers both collections from a single counter.
--- @param target string?
--- @param opts vim.api.keyset.create_user_command.command_args? window modifiers
function M.open(target, opts)
  view.command(target, 'prs', opts)
end

return M
