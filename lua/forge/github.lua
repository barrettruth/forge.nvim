local forge = require('forge')

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

local function nwo()
  local url = forge.remote_web_url()
  return url:match('github%.com/(.+)$') or ''
end

---@param state string
---@return string[]
function M:list_pr_json_cmd(state)
  return {
    'gh',
    'pr',
    'list',
    '--limit',
    tostring(forge.config().display.limits.pulls),
    '--state',
    state,
    '--json',
    'number,title,headRefName,state,author,createdAt',
  }
end

---@param state string
---@return string[]
function M:list_issue_json_cmd(state)
  return {
    'gh',
    'issue',
    'list',
    '--limit',
    tostring(forge.config().display.limits.issues),
    '--state',
    state,
    '--json',
    'number,title,state,author,createdAt',
  }
end

---@param kind string
---@param num string
function M:view_web(kind, num)
  vim.system({ 'gh', kind, 'view', num, '--web' })
end

---@param loc string
---@param branch string
function M:browse(loc, branch)
  vim.system({ 'gh', 'browse', loc, '--branch', branch })
end

function M:browse_branch(branch)
  vim.system({ 'gh', 'browse', '--branch', branch })
end

function M:browse_commit(sha)
  vim.system({ 'gh', 'browse', sha })
end

function M:checkout_cmd(num)
  return { 'gh', 'pr', 'checkout', num }
end

---@param num string
---@return string[]
function M:fetch_pr(num)
  return { 'git', 'fetch', 'origin', ('pull/%s/head:pr-%s'):format(num, num) }
end

---@param num string
---@return string[]
function M:pr_base_cmd(num)
  return {
    'gh',
    'pr',
    'view',
    num,
    '--json',
    'baseRefName',
    '--jq',
    '.baseRefName',
  }
end

---@param branch string
---@return string[]
function M:pr_for_branch_cmd(branch)
  return {
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
end

---@param num string
---@return string
function M:checks_cmd(num)
  return ('gh pr checks %s'):format(num)
end

---@param num string
---@return string[]
function M:checks_json_cmd(num)
  return {
    'gh',
    'pr',
    'checks',
    num,
    '--json',
    'name,bucket,link,state,startedAt,completedAt',
  }
end

---@param run_id string
---@param failed_only boolean
---@param job_id string?
---@return string[]
function M:check_log_cmd(run_id, failed_only, job_id)
  local lines = forge.config().ci.lines
  local flag = failed_only and '--log-failed' or '--log'
  local job_flag = job_id and (' --job %s'):format(job_id) or ''
  return {
    'sh',
    '-c',
    ('gh run view %s -R %s%s %s | tail -n %d'):format(run_id, nwo(), job_flag, flag, lines),
  }
end

---@param run_id string
---@return string[]
function M:steps_cmd(run_id)
  return { 'gh', 'run', 'view', run_id, '-R', nwo(), '--json', 'jobs' }
end

---@param id string
---@param opts? { job_id?: string, log?: boolean, failed?: boolean }
---@return string[]
function M:view_cmd(id, opts)
  opts = opts or {}
  local cmd = { 'gh', 'run', 'view', id, '-R', nwo() }
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
---@return string[]
function M:watch_cmd(id)
  return { 'gh', 'run', 'watch', id, '-R', nwo() }
end

---@param id string
---@return string[]
function M:run_status_cmd(id)
  return { 'gh', 'run', 'view', id, '-R', nwo(), '--json', 'status,conclusion' }
end

function M:run_log_cmd(id, failed_only)
  local lines = forge.config().ci.lines
  local flag = failed_only and '--log-failed' or '--log'
  return {
    'sh',
    '-c',
    ('gh run view %s -R %s %s | tail -n %d'):format(id, nwo(), flag, lines),
  }
end

function M:list_runs_json_cmd(branch)
  local cmd = {
    'gh',
    'run',
    'list',
    '--json',
    'databaseId,name,headBranch,status,conclusion,event,url,createdAt',
    '--limit',
    tostring(forge.config().display.limits.runs),
  }
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
    name = entry.name or '',
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
function M:merge_cmd(num, method)
  return { 'gh', 'pr', 'merge', num, '--' .. method }
end

---@param num string
---@return string[]
function M:approve_cmd(num)
  return { 'gh', 'pr', 'review', num, '--approve' }
end

---@param num string
---@return string[]
function M:close_cmd(num)
  return { 'gh', 'pr', 'close', num }
end

---@param num string
---@return string[]
function M:reopen_cmd(num)
  return { 'gh', 'pr', 'reopen', num }
end

---@param num string
---@return string[]
function M:close_issue_cmd(num)
  return { 'gh', 'issue', 'close', num }
end

---@param num string
---@return string[]
function M:reopen_issue_cmd(num)
  return { 'gh', 'issue', 'reopen', num }
end

---@param num string
---@return string[]
function M:fetch_pr_details_cmd(num)
  return {
    'gh',
    'pr',
    'view',
    num,
    '--json',
    'title,body,isDraft,labels,assignees,reviewRequests,milestone',
  }
end

---@param num string
---@param title string
---@param body string
---@param reviewers string[]?
---@param labels string[]?
---@param assignees string[]?
---@param milestone string?
---@return string[]
function M:update_pr_cmd(num, title, body, reviewers, labels, assignees, milestone)
  local cmd = { 'gh', 'pr', 'edit', num, '--title', title, '--body', body }
  for _, r in ipairs(reviewers or {}) do
    table.insert(cmd, '--add-reviewer')
    table.insert(cmd, r)
  end
  for _, l in ipairs(labels or {}) do
    table.insert(cmd, '--add-label')
    table.insert(cmd, l)
  end
  for _, a in ipairs(assignees or {}) do
    table.insert(cmd, '--add-assignee')
    table.insert(cmd, a)
  end
  if milestone and milestone ~= '' then
    table.insert(cmd, '--milestone')
    table.insert(cmd, milestone)
  end
  return cmd
end

---@param json table
---@return { title: string, body: string, draft: boolean, reviewers: string[], labels: string[], assignees: string[], milestone: string }
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
    labels = labels,
    assignees = assignees,
    reviewers = reviewers,
    milestone = milestone,
  }
end

---@param title string
---@param body string
---@param base string
---@param draft boolean
---@param reviewers string[]?
---@param labels string[]?
---@param assignees string[]?
---@param milestone string?
---@return string[]
function M:create_pr_cmd(title, body, base, draft, reviewers, labels, assignees, milestone)
  local cmd = { 'gh', 'pr', 'create', '--title', title, '--body', body, '--base', base }
  if draft then
    table.insert(cmd, '--draft')
  end
  for _, r in ipairs(reviewers or {}) do
    table.insert(cmd, '--reviewer')
    table.insert(cmd, r)
  end
  for _, l in ipairs(labels or {}) do
    table.insert(cmd, '--label')
    table.insert(cmd, l)
  end
  for _, a in ipairs(assignees or {}) do
    table.insert(cmd, '--assignee')
    table.insert(cmd, a)
  end
  if milestone and milestone ~= '' then
    table.insert(cmd, '--milestone')
    table.insert(cmd, milestone)
  end
  return cmd
end

---@return string[]
function M:create_pr_web_cmd()
  return { 'gh', 'pr', 'create', '--web' }
end

---@param title string
---@param body string
---@param labels string[]?
---@param assignees string[]?
---@param milestone string?
---@return string[]
function M:create_issue_cmd(title, body, labels, assignees, milestone)
  local cmd = { 'gh', 'issue', 'create', '--title', title, '--body', body }
  for _, l in ipairs(labels or {}) do
    table.insert(cmd, '--label')
    table.insert(cmd, l)
  end
  for _, a in ipairs(assignees or {}) do
    table.insert(cmd, '--assignee')
    table.insert(cmd, a)
  end
  if milestone and milestone ~= '' then
    table.insert(cmd, '--milestone')
    table.insert(cmd, milestone)
  end
  return cmd
end

---@return string[]
function M:create_issue_web_cmd()
  return { 'gh', 'issue', 'create', '--web' }
end

---@return string[]
function M:issue_template_paths()
  return {
    '.github/ISSUE_TEMPLATE.md',
    '.github/ISSUE_TEMPLATE/',
  }
end

---@return string[]
function M:default_branch_cmd()
  return { 'gh', 'repo', 'view', '--json', 'defaultBranchRef', '--jq', '.defaultBranchRef.name' }
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
function M:draft_toggle_cmd(num, is_draft)
  if is_draft then
    return { 'gh', 'pr', 'ready', num }
  end
  return { 'gh', 'pr', 'ready', num, '--undo' }
end

---@return forge.RepoInfo
function M:repo_info()
  local result = vim
    .system({
      'gh',
      'repo',
      'view',
      nwo(),
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
function M:pr_state(num)
  local result = vim
    .system({
      'gh',
      'pr',
      'view',
      num,
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

function M:list_releases_json_cmd()
  return {
    'gh',
    'release',
    'list',
    '--json',
    'tagName,name,isDraft,isPrerelease,isLatest,publishedAt',
    '--limit',
    tostring(forge.config().display.limits.releases),
  }
end

---@param tag string
function M:browse_release(tag)
  vim.system({ 'gh', 'release', 'view', tag, '--web' })
end

---@param tag string
---@return string[]
function M:delete_release_cmd(tag)
  return { 'gh', 'release', 'delete', tag, '--yes' }
end

return M
