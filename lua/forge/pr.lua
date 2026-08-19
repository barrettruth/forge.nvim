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

--- When to offer one of the two namings a merge has.
---
--- Both send the same document: `mergePullRequest` has no bypass field, and
--- github applies one server-side to whoever holds it, so what is chosen here
--- is a word. `viewerCanMergeAsAdmin` is false for an admin with nothing to
--- bypass, so the two are never offered together, and nothing is refused on
--- it either way: github decides that when asked, as it does for every merge.
--- @param can string the field saying github would take this method at all
--- @param bypass boolean which of the pair this is
--- @return fun(var: forge.ItemVar): boolean
local function naming(can, bypass)
  return function(var)
    return var.state == 'OPEN' and var[can] == true and (var.can_bypass == true) == bypass
  end
end

--- When to offer a merge that waits for github to allow it.
---
--- `viewerCanEnableAutoMerge` answers the whole of whether github would take
--- one, the repository's switch and your access included, and it is false on a
--- pull request that could merge now. The method still has to be one the
--- repository and its ruleset would take, since that is checked when the wait
--- ends rather than when it starts.
--- @param can string
--- @return fun(var: forge.ItemVar): boolean
local function waiting(can)
  return function(var)
    return var.state == 'OPEN' and var[can] == true and var.can_auto == true and var.auto == nil
  end
end

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
  collection = 'prs',
  --- A draft is OPEN with a flag, so it is resolved before this is consulted.
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
  --- A pull request is the only view with checks behind it, so "dc" is bound
  --- here rather than everywhere. An issue has no CI, and a key that exists
  --- only to refuse is worse than no key.
  item_maps = {
    { 'cc', '<Plug>(forge-act)', 'do something to this {one}' },
    { 'dc', '<Plug>(forge-checks)', "show this {one}'s checks in ci.nvim" },
    { 'dd', '<Plug>(forge-diff)', "show this {one}'s diff in diffs.nvim" },
    { 'dl', '<Plug>(forge-log)', "show this {one}'s commits in fugitive" },
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
      can_bypass = node.viewerCanMergeAsAdmin == true,
      --- github only offers auto-merge on a pull request it will not merge
      --- now, so this is true in much the same places `can_bypass` is: it is
      --- the other answer to a merge being blocked, and the reversible one.
      can_auto = node.viewerCanEnableAutoMerge == true,
      can_unauto = node.viewerCanDisableAutoMerge == true,
      --- A base branch with a queue refuses every direct merge, so `merges`
      --- offers none and the queue is the only way in.
      queued = node.isMergeQueueEnabled == true,
      in_queue = node.isInMergeQueue == true,
      --- The method a merge already waiting would use, and nothing when none
      --- is waiting.
      auto = vim.tbl_get(node, 'autoMergeRequest', 'mergeMethod'),
      --- The message github itself would write, honouring what the repository
      --- sets its commit title and body to be. Rebase is asked for neither:
      --- github answers "" for both, which is it saying there is no message.
      merge = {
        SQUASH = { headline = node.squashHeadline or '', body = node.squashBody or '' },
        MERGE = { headline = node.commitHeadline or '', body = node.commitBody or '' },
      },
      base = node.baseRefName,
      --- A fork says whose branch it is, the name alone not saying.
      head = node.isCrossRepository and ('%s:%s'):format(
        vim.tbl_get(node, 'headRepositoryOwner', 'login') or '?',
        node.headRefName or '?'
      ) or node.headRefName,
      remote = repo.url,
    }
  end,
  --- Draft is a flag on an open pull request, and github leaves it set when
  --- one is closed; a closed draft is closed.
  state = function(node)
    return (node.state == 'OPEN' and node.isDraft) and 'DRAFT' or node.state
  end,
  --- The branches take the room a title would, so there is nothing to say
  --- here: |b:forge| carries them and the winbar draws them itself.
  about = function()
    return ''
  end,
  --- Only the outstanding ones: github drops a request when its reviewer
  --- answers, and the answer shows in the winbar and in the conversation.
  rows = function(node)
    local asked = {}
    for _, request in ipairs(vim.tbl_get(node, 'reviewRequests', 'nodes') or {}) do
      asked[#asked + 1] = request.requestedReviewer
    end
    return {
      { key = 'Reviewers', values = text.logins({ nodes = asked }), group = text.LOGIN },
    }
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
      write = 'draft',
      when = function(var)
        return var.state == 'OPEN' and var.can_update == true
      end,
    },
    {
      label = 'Ready for review',
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
    --- Last, and each already weighed by `merges`: what is left to ask here is
    --- only whether the pull request is open, since a draft cannot be merged
    --- and DRAFT is resolved before any of this is read.
    ---
    --- Named twice and offered once, as `naming` says. Interleaved so the pair
    --- stands where the one entry did, whichever of them the answer is.
    ---
    --- Joining a queue is not merging; the queue merges when it gets there,
    --- and leaving it is a keystroke, so these stand where the merges would.
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
    --- Waiting comes before merging, for the same reason closing comes after
    --- editing: a merge that waits can be called off, and one that happens
    --- cannot. github calls it auto-merge, so this does too.
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
    --- The two that write a commit open a buffer for its message; a rebase
    --- writes none, so it goes straight out.
    { label = 'Squash and merge', run = squashing, when = naming('can_squash', false) },
    { label = 'Squash and merge (bypass)', run = squashing, when = naming('can_squash', true) },
    {
      label = 'Create a merge commit',
      run = committing,
      when = naming('can_merge_commit', false),
    },
    {
      label = 'Create a merge commit (bypass)',
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

--- Open the pull request for the branch checked out here.
---
--- The branch is found locally and the pull request is asked for by name, so a
--- fork is answered by the repository the pull request is actually on.
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
      view.create(uri.of(found.project, { collection = 'prs' }))
      return
    end
    local item = { collection = 'prs', number = found.number }
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
