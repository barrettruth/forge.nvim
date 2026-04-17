local forge = require('forge')
local log = require('forge.logger')
local submission = require('forge.submission')

---@class forge.GitHub: forge.Forge
local M = {
  name = 'github',
  cli = 'gh',
  kinds = { issue = 'issue', pr = 'pr' },
  labels = {
    issue = 'Issues',
    pr = 'PRs',
    pr_one = 'PR',
    pr_full = 'Pull Requests',
    ci = 'CI/CD',
  },
  capabilities = {
    draft = true,
    reviewers = true,
    per_pr_checks = true,
    ci_json = true,
  },
  submission = {
    issue = {
      create = { labels = true, assignees = true, milestone = true },
      update = { labels = true, assignees = true, milestone = true },
    },
    pr = {
      create = { draft = true, reviewers = true, labels = true, assignees = true, milestone = true },
      update = { draft = true, reviewers = true, labels = true, assignees = true, milestone = true },
    },
  },
  pr_fields = {
    number = 'number',
    title = 'title',
    branch = 'headRefName',
    state = 'state',
    author = 'author',
    created_at = 'createdAt',
  },
  issue_fields = {
    number = 'number',
    title = 'title',
    state = 'state',
    author = 'author',
    created_at = 'createdAt',
  },
  release_fields = {
    tag = 'tagName',
    title = 'name',
    is_draft = 'isDraft',
    is_prerelease = 'isPrerelease',
    is_latest = 'isLatest',
    published_at = 'publishedAt',
  },
}

local function nwo(scope)
  local current = scope or forge.current_scope(M.name)
  return forge.scope_repo_arg(current) or ''
end

local function tty_env()
  return { 'env', 'GH_FORCE_TTY=1000', 'CLICOLOR_FORCE=1' }
end

local function open_browse_url(cmd)
  local browse_cmd = vim.deepcopy(cmd)
  table.insert(browse_cmd, '--no-browser')
  vim.system(browse_cmd, { text = true }, function(result)
    vim.schedule(function()
      local url = vim.trim(result.stdout or '')
      if result.code ~= 0 or url == '' then
        local err = vim.trim(result.stderr or '')
        log.error(err ~= '' and err or 'browse failed')
        return
      end
      local _, err = vim.ui.open(url)
      if err then
        log.error(err)
      end
    end)
  end)
end

local function append_csv(cmd, flag, values)
  if values and #values > 0 then
    table.insert(cmd, flag)
    table.insert(cmd, table.concat(values, ','))
  end
end

---@param state string
---@param limit integer?
---@return string[]
function M:list_pr_json_cmd(state, limit, scope)
  local cmd = {
    'gh',
    'pr',
    'list',
    '--limit',
    tostring(limit or forge.config().display.limits.pulls),
    '--state',
    state,
    '--json',
    'number,title,headRefName,state,author,createdAt,url',
  }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

---@param state string
---@param limit integer?
---@return string[]
function M:list_issue_json_cmd(state, limit, scope)
  local cmd = {
    'gh',
    'issue',
    'list',
    '--limit',
    tostring(limit or forge.config().display.limits.issues),
    '--state',
    state,
    '--json',
    'number,title,state,author,createdAt',
  }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

---@param kind string
---@param num string
function M:view_web(kind, num, scope)
  local cmd = { 'gh', kind, 'view', num, '--web' }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  vim.system(cmd)
end

---@param loc string
---@param branch string
function M:browse(loc, branch, scope)
  local cmd = { 'gh', 'browse', loc, '--branch', branch }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  open_browse_url(cmd)
end

function M:browse_branch(branch, scope)
  local cmd = { 'gh', 'browse', '--branch', branch }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  open_browse_url(cmd)
end

function M:browse_commit(commit, scope)
  local cmd = { 'gh', 'browse', commit }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  open_browse_url(cmd)
end

local LIST_PATHS = {
  pr = '/pulls',
  issue = '/issues',
  ci = '/actions',
  release = '/releases',
}

---@param kind forge.WebKind
---@return string?
function M:list_web_url(kind, scope)
  local base = forge.remote_web_url(scope)
  if not base or base == '' then
    return nil
  end
  local path = LIST_PATHS[kind]
  if not path then
    return nil
  end
  return base .. path
end

function M:checkout_cmd(num, scope)
  local cmd = { 'gh', 'pr', 'checkout', num }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

---@param num string
---@return string[]
function M:fetch_pr(num, scope)
  local current = forge.current_scope(M.name)
  local remote = 'origin'
  if
    scope
    and forge.scope_key(scope) ~= ''
    and forge.scope_key(scope) ~= forge.scope_key(current)
  then
    remote = forge.remote_web_url(scope) .. '.git'
  end
  return { 'git', 'fetch', remote, ('pull/%s/head:pr-%s'):format(num, num) }
end

---@param num string
---@return string[]
function M:pr_base_cmd(num, scope)
  return {
    'gh',
    'pr',
    'view',
    num,
    '-R',
    nwo(scope),
    '--json',
    'baseRefName',
    '--jq',
    '.baseRefName',
  }
end

---@param branch string
---@return string[]
function M:pr_for_branch_cmd(branch, scope)
  local cmd = {
    'gh',
    'pr',
    'list',
    '--head',
    branch,
    '--json',
    'number',
    '--jq',
    '.[0].number',
  }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

---@param num string
---@return string
function M:checks_cmd(num)
  return ('gh pr checks %s'):format(num)
end

---@param num string
---@return string[]
function M:checks_json_cmd(num, scope)
  return {
    'gh',
    'pr',
    'checks',
    num,
    '-R',
    nwo(scope),
    '--json',
    'name,bucket,link,state,startedAt,completedAt',
  }
end

---@param run_id string
---@param failed_only boolean
---@param job_id string?
---@return string[]
function M:check_log_cmd(run_id, failed_only, job_id, scope)
  local lines = forge.config().ci.lines
  local flag = failed_only and '--log-failed' or '--log'
  local job_flag = job_id and (' --job %s'):format(job_id) or ''
  return {
    'sh',
    '-c',
    ('gh run view %s -R %s%s %s | tail -n %d'):format(run_id, nwo(scope), job_flag, flag, lines),
  }
end

---@param run_id string
---@return string[]
function M:steps_cmd(run_id, scope)
  return { 'gh', 'run', 'view', run_id, '-R', nwo(scope), '--json', 'jobs' }
end

---@param id string
---@param opts? forge.RunViewOpts
---@return string[]
function M:view_cmd(id, opts)
  opts = opts or {}
  local cmd = tty_env()
  vim.list_extend(cmd, { 'gh', 'run', 'view', id, '-R', nwo(opts.scope) })
  if opts.job_id then
    table.insert(cmd, '--job')
    table.insert(cmd, opts.job_id)
  end
  if opts.log then
    table.insert(cmd, opts.failed and '--log-failed' or '--log')
  end
  return cmd
end

---@param id string
---@return string?
function M:run_web_url(id, scope)
  local base = forge.remote_web_url(scope)
  if not base or base == '' then
    return nil
  end
  return ('%s/actions/runs/%s'):format(base, id)
end

---@param run_id string
---@param job_id string
---@return string?
function M:job_web_url(run_id, job_id, scope)
  local run_url = self:run_web_url(run_id, scope)
  if not run_url or run_url == '' then
    return nil
  end
  return ('%s/job/%s'):format(run_url, job_id)
end

---@param id string
---@return string[]
function M:summary_json_cmd(id, scope)
  local jq = table.concat({
    '{displayTitle,name,status,conclusion,event,url,',
    'jobs:[.jobs[]|{databaseId,name,status,conclusion,url,',
    'startedAt,completedAt,',
    'steps:[.steps[]|{name,status,conclusion,number}]}]}',
  }, '')
  return {
    'gh',
    'run',
    'view',
    id,
    '-R',
    nwo(scope),
    '--json',
    'displayTitle,name,status,conclusion,event,url,jobs',
    '--jq',
    jq,
  }
end

---@param id string
---@return string[]
function M:watch_cmd(id, scope)
  return { 'gh', 'run', 'watch', id, '-R', nwo(scope) }
end

---@param id string
---@return string[]
function M:run_status_cmd(id, scope)
  return { 'gh', 'run', 'view', id, '-R', nwo(scope), '--json', 'status,conclusion' }
end

function M:run_log_cmd(id, failed_only, scope)
  local lines = forge.config().ci.lines
  local flag = failed_only and '--log-failed' or '--log'
  return {
    'sh',
    '-c',
    ('gh run view %s -R %s %s | tail -n %d'):format(id, nwo(scope), flag, lines),
  }
end

function M:list_runs_json_cmd(branch, scope, limit)
  local cmd = {
    'gh',
    'run',
    'list',
    '--json',
    'databaseId,name,headBranch,status,conclusion,event,url,createdAt',
    '--limit',
    tostring(limit or forge.config().display.limits.runs),
  }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  if branch then
    table.insert(cmd, '--branch')
    table.insert(cmd, branch)
  end
  return cmd
end

function M:normalize_run(entry)
  local status = entry.status or ''
  if status == 'completed' then
    status = entry.conclusion or 'unknown'
  end
  return {
    id = tostring(entry.databaseId or ''),
    name = entry.displayTitle or entry.name or '',
    branch = entry.headBranch or '',
    status = status,
    event = entry.event or '',
    url = entry.url or '',
    created_at = entry.createdAt or '',
  }
end

---@param num string
---@param method string
---@return string[]
function M:merge_cmd(num, method, scope)
  local cmd = { 'gh', 'pr', 'merge', num }
  if method and method ~= '' then
    table.insert(cmd, '--' .. method)
  end
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

---@param num string
---@return string[]
function M:approve_cmd(num, scope)
  local cmd = { 'gh', 'pr', 'review', num, '--approve' }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

---@param num string
---@return string[]
function M:close_cmd(num, scope)
  local cmd = { 'gh', 'pr', 'close', num }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

---@param num string
---@return string[]
function M:reopen_cmd(num, scope)
  local cmd = { 'gh', 'pr', 'reopen', num }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

---@param num string
---@return string[]
function M:close_issue_cmd(num, scope)
  local cmd = { 'gh', 'issue', 'close', num }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

---@param num string
---@return string[]
function M:reopen_issue_cmd(num, scope)
  local cmd = { 'gh', 'issue', 'reopen', num }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

---@param num string
---@return string[]
function M:fetch_pr_details_cmd(num, scope)
  return {
    'gh',
    'pr',
    'view',
    num,
    '-R',
    nwo(scope),
    '--json',
    'title,body,isDraft,headRefName,baseRefName,labels,assignees,reviewRequests,milestone,url',
  }
end

function M:fetch_issue_details_cmd(num, scope)
  return {
    'gh',
    'issue',
    'view',
    num,
    '-R',
    nwo(scope),
    '--json',
    'title,body,labels,assignees,milestone,url',
  }
end

---@param num string
---@param title string
---@param body string
---@return string[]
function M:update_pr_cmd(num, title, body, scope, metadata, previous)
  local cmd = { 'gh', 'pr', 'edit', num, '--title', title, '--body', body }
  local current = submission.filter(self, 'pr', 'update', metadata)
  local before = previous or { labels = {}, assignees = {}, reviewers = {}, milestone = '' }
  local add_labels, remove_labels = submission.diff(before.labels, current.labels)
  local add_assignees, remove_assignees = submission.diff(before.assignees, current.assignees)
  local add_reviewers, remove_reviewers = submission.diff(before.reviewers, current.reviewers)
  append_csv(cmd, '--add-label', add_labels)
  append_csv(cmd, '--remove-label', remove_labels)
  append_csv(cmd, '--add-assignee', add_assignees)
  append_csv(cmd, '--remove-assignee', remove_assignees)
  append_csv(cmd, '--add-reviewer', add_reviewers)
  append_csv(cmd, '--remove-reviewer', remove_reviewers)
  if current.milestone ~= (before.milestone or '') then
    if current.milestone == '' then
      table.insert(cmd, '--remove-milestone')
    else
      table.insert(cmd, '--milestone')
      table.insert(cmd, current.milestone)
    end
  end
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

function M:update_issue_cmd(num, title, body, scope, metadata, previous)
  local cmd = { 'gh', 'issue', 'edit', num, '--title', title, '--body', body }
  local current = submission.filter(self, 'issue', 'update', metadata)
  local before = previous or { labels = {}, assignees = {}, milestone = '' }
  local add_labels, remove_labels = submission.diff(before.labels, current.labels)
  local add_assignees, remove_assignees = submission.diff(before.assignees, current.assignees)
  append_csv(cmd, '--add-label', add_labels)
  append_csv(cmd, '--remove-label', remove_labels)
  append_csv(cmd, '--add-assignee', add_assignees)
  append_csv(cmd, '--remove-assignee', remove_assignees)
  if current.milestone ~= (before.milestone or '') then
    if current.milestone == '' then
      table.insert(cmd, '--remove-milestone')
    else
      table.insert(cmd, '--milestone')
      table.insert(cmd, current.milestone)
    end
  end
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

---@param json table
---@return forge.PRDetails
function M:parse_pr_details(json)
  local labels = {}
  for _, l in ipairs(json.labels or {}) do
    table.insert(labels, l.name or '')
  end
  local assignees = {}
  for _, a in ipairs(json.assignees or {}) do
    table.insert(assignees, a.login or '')
  end
  local reviewers = {}
  for _, r in ipairs(json.reviewRequests or {}) do
    table.insert(reviewers, r.login or '')
  end
  local milestone = ''
  if type(json.milestone) == 'table' and json.milestone.title then
    milestone = json.milestone.title
  end
  return {
    title = json.title or '',
    body = json.body or '',
    draft = json.isDraft == true,
    head_branch = json.headRefName or '',
    base_branch = json.baseRefName or '',
    labels = labels,
    assignees = assignees,
    reviewers = reviewers,
    milestone = milestone,
  }
end

function M:parse_issue_details(json)
  local labels = {}
  for _, l in ipairs(json.labels or {}) do
    table.insert(labels, l.name or '')
  end
  local assignees = {}
  for _, a in ipairs(json.assignees or {}) do
    table.insert(assignees, a.login or '')
  end
  local milestone = ''
  if type(json.milestone) == 'table' and json.milestone.title then
    milestone = json.milestone.title
  end
  return {
    title = json.title or '',
    body = json.body or '',
    labels = labels,
    assignees = assignees,
    milestone = milestone,
  }
end

---@param title string
---@param body string
---@param base string
---@param draft boolean
---@return string[]
function M:create_pr_cmd(title, body, base, draft, scope, metadata)
  local cmd = { 'gh', 'pr', 'create', '--title', title, '--body', body, '--base', base }
  local current = metadata and submission.filter(self, 'pr', 'create', metadata) or nil
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  if (current and current.draft) or (not current and draft) then
    table.insert(cmd, '--draft')
  end
  append_csv(cmd, '--label', current and current.labels or {})
  append_csv(cmd, '--assignee', current and current.assignees or {})
  append_csv(cmd, '--reviewer', current and current.reviewers or {})
  if current and current.milestone ~= '' then
    table.insert(cmd, '--milestone')
    table.insert(cmd, current.milestone)
  end
  return cmd
end

---@return string[]
function M:create_pr_web_cmd(scope, head_scope, head_branch, base_branch)
  local cmd = { 'gh', 'pr', 'create', '--web' }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  if base_branch and base_branch ~= '' then
    table.insert(cmd, '--base')
    table.insert(cmd, base_branch)
  end
  local head = head_branch
  if
    head
    and head ~= ''
    and head_scope
    and scope
    and forge.scope_key(head_scope) ~= ''
    and forge.scope_key(head_scope) ~= forge.scope_key(scope)
    and head_scope.owner
    and head_scope.owner ~= ''
  then
    head = head_scope.owner .. ':' .. head
  end
  if head and head ~= '' then
    table.insert(cmd, '--head')
    table.insert(cmd, head)
  end
  return cmd
end

---@param title string
---@param body string
---@param labels string[]?
---@return string[]
function M:create_issue_cmd(title, body, labels, scope, metadata)
  local cmd = { 'gh', 'issue', 'create', '--title', title, '--body', body }
  local current = metadata and submission.filter(self, 'issue', 'create', metadata) or nil
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  local effective_labels = current and current.labels or (labels or {})
  append_csv(cmd, '--label', effective_labels)
  append_csv(cmd, '--assignee', current and current.assignees or {})
  if current and current.milestone ~= '' then
    table.insert(cmd, '--milestone')
    table.insert(cmd, current.milestone)
  end
  return cmd
end

---@return string?
function M:create_issue_web_url(scope)
  local url = forge.remote_web_url(scope)
  if url == '' then
    return nil
  end
  return url .. '/issues/new'
end

---@return string[]
function M:issue_template_paths()
  return {
    '.github/ISSUE_TEMPLATE.md',
    '.github/ISSUE_TEMPLATE/',
  }
end

---@return string[]
function M:default_branch_cmd(scope)
  return {
    'gh',
    'repo',
    'view',
    nwo(scope),
    '--json',
    'defaultBranchRef',
    '--jq',
    '.defaultBranchRef.name',
  }
end

---@return string[]
function M:template_paths()
  return {
    '.github/pull_request_template.md',
    '.github/PULL_REQUEST_TEMPLATE.md',
    '.github/PULL_REQUEST_TEMPLATE/',
  }
end

---@param num string
---@param is_draft boolean
---@return string[]?
function M:draft_toggle_cmd(num, is_draft, scope)
  if is_draft then
    return { 'gh', 'pr', 'ready', num, '-R', nwo(scope) }
  end
  return { 'gh', 'pr', 'ready', num, '--undo', '-R', nwo(scope) }
end

---@return forge.RepoInfo
function M:repo_info(scope)
  local result = vim
    .system({
      'gh',
      'repo',
      'view',
      nwo(scope),
      '--json',
      'viewerPermission,squashMergeAllowed,rebaseMergeAllowed,mergeCommitAllowed',
    }, { text = true })
    :wait()

  local ok, data = pcall(vim.json.decode, result.stdout or '{}')
  if not ok or type(data) ~= 'table' then
    data = {}
  end
  local methods = {}
  if data.squashMergeAllowed then
    table.insert(methods, 'squash')
  end
  if data.rebaseMergeAllowed then
    table.insert(methods, 'rebase')
  end
  if data.mergeCommitAllowed then
    table.insert(methods, 'merge')
  end

  return {
    permission = (data.viewerPermission or 'READ'):upper(),
    merge_methods = methods,
  }
end

---@param num string
---@return forge.PRState
function M:pr_state(num, scope)
  local result = vim
    .system({
      'gh',
      'pr',
      'view',
      num,
      '-R',
      nwo(scope),
      '--json',
      'state,mergeable,reviewDecision,isDraft',
    }, { text = true })
    :wait()

  local ok, data = pcall(vim.json.decode, result.stdout or '{}')
  if not ok or type(data) ~= 'table' then
    data = {}
  end
  return {
    state = data.state or 'UNKNOWN',
    mergeable = data.mergeable or 'UNKNOWN',
    review_decision = data.reviewDecision or '',
    is_draft = data.isDraft == true,
  }
end

function M:list_releases_json_cmd(scope, limit)
  local cmd = {
    'gh',
    'release',
    'list',
    '--json',
    'tagName,name,isDraft,isPrerelease,isLatest,publishedAt',
    '--limit',
    tostring(limit or forge.config().display.limits.releases),
  }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  return cmd
end

---@param tag string
function M:browse_release(tag, scope)
  local cmd = { 'gh', 'release', 'view', tag, '--web' }
  local repo = nwo(scope)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  vim.system(cmd)
end

---@param tag string
---@return string[]
function M:delete_release_cmd(tag, scope)
  return { 'gh', 'release', 'delete', tag, '--yes', '-R', nwo(scope) }
end

return M
