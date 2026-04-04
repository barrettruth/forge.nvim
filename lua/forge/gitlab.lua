local forge = require('forge')

---@class forge.GitLab: forge.Forge
local M = {
  name = 'gitlab',
  cli = 'glab',
  kinds = { issue = 'issue', pr = 'mr' },
  labels = {
    issue = 'Issues',
    pr = 'MRs',
    pr_one = 'MR',
    pr_full = 'Merge Requests',
    ci = 'CI/CD',
  },
  capabilities = {
    draft = true,
    reviewers = true,
    per_pr_checks = true,
    ci_json = true,
  },
  pr_fields = {
    number = 'iid',
    title = 'title',
    branch = 'source_branch',
    state = 'state',
    author = 'author',
    created_at = 'created_at',
  },
  issue_fields = {
    number = 'iid',
    title = 'title',
    state = 'state',
    author = 'author',
    created_at = 'created_at',
  },
  release_fields = {
    tag = 'tag_name',
    title = 'name',
    published_at = 'released_at',
  },
}

---@param state string
---@return string[]
function M:list_pr_json_cmd(state)
  local cmd = {
    'glab',
    'mr',
    'list',
    '--per-page',
    tostring(forge.config().display.limits.pulls),
    '--output',
    'json',
  }
  if state == 'closed' then
    table.insert(cmd, '--closed')
  elseif state == 'all' then
    table.insert(cmd, '--all')
  end
  return cmd
end

---@param state string
---@return string[]
function M:list_issue_json_cmd(state)
  local cmd = {
    'glab',
    'issue',
    'list',
    '--per-page',
    tostring(forge.config().display.limits.issues),
    '--output',
    'json',
  }
  if state == 'closed' then
    table.insert(cmd, '--closed')
  elseif state == 'all' then
    table.insert(cmd, '--all')
  end
  return cmd
end

---@param kind string
---@param num string
function M:view_web(kind, num)
  vim.system({ 'glab', kind, 'view', num, '--web' })
end

---@param loc string
---@param branch string
function M:browse(loc, branch)
  local base = forge.remote_web_url()
  local file, lines = loc:match('^(.+):(.+)$')
  vim.ui.open(('%s/-/blob/%s/%s#L%s'):format(base, branch, file, lines))
end

function M:browse_branch(branch)
  local base = forge.remote_web_url()
  vim.ui.open(base .. '/-/tree/' .. branch)
end

function M:browse_commit(sha)
  local base = forge.remote_web_url()
  vim.ui.open(base .. '/-/commit/' .. sha)
end

function M:checkout_cmd(num)
  return { 'glab', 'mr', 'checkout', num }
end

---@param num string
---@return string[]
function M:fetch_pr(num)
  return {
    'git',
    'fetch',
    'origin',
    ('merge-requests/%s/head:mr-%s'):format(num, num),
  }
end

---@param num string
---@return string[]
function M:pr_base_cmd(num)
  return {
    'sh',
    '-c',
    ('glab mr view %s -F json | jq -r .target_branch'):format(num),
  }
end

---@param branch string
---@return string[]
function M:pr_for_branch_cmd(branch)
  return {
    'sh',
    '-c',
    ("glab mr list --source-branch '%s' -F json | jq -r '.[0].iid // empty'"):format(branch),
  }
end

---@param num string
---@return string[]
function M:checks_json_cmd(num)
  local jq = [=[
    [.[] | {
      name: .name,
      bucket: (if .status == "success" then "pass"
               elif .status == "failed" then "fail"
               elif (.status == "running" or .status == "pending" or .status == "created") then "pending"
               elif .status == "canceled" then "cancel"
               else "skipping" end),
      link: .web_url,
      startedAt: .started_at,
      completedAt: .finished_at,
      run_id: (.id | tostring)
    }]
  ]=]
  return {
    'sh',
    '-c',
    ('PID=$(glab api "projects/:id/merge_requests/%s/pipelines?per_page=1" 2>/dev/null | jq -r ".[0].id // empty") && [ -n "$PID" ] && glab api "projects/:id/pipelines/$PID/jobs?per_page=100" 2>/dev/null | jq -r \'%s\''):format(
      num,
      jq:gsub('%s+', ' ')
    ),
  }
end

---@param num string
---@return string
function M:checks_cmd(num)
  local _ = num
  return 'glab ci list'
end

---@param run_id string
---@param failed_only boolean
---@param job_id string?
---@return string[]
function M:check_log_cmd(run_id, failed_only, job_id)
  local _ = failed_only
  local lines = forge.config().ci.lines
  local id = job_id or run_id
  return {
    'sh',
    '-c',
    ('glab ci trace %s | tail -n %d'):format(id, lines),
  }
end

---@param run_id string
---@return string[]
function M:check_tail_cmd(run_id)
  return { 'glab', 'ci', 'trace', run_id }
end

---@param run_id string
---@return string[]
function M:live_tail_cmd(run_id)
  return { 'glab', 'ci', 'trace', run_id }
end

---@param id string?
---@return string[]
function M:watch_cmd(id)
  local cmd = { 'glab', 'ci', 'view' }
  if id then
    table.insert(cmd, '-p')
    table.insert(cmd, id)
  end
  return cmd
end

function M:list_runs_json_cmd(branch)
  local cmd = {
    'glab',
    'ci',
    'list',
    '--output',
    'json',
    '--per-page',
    tostring(forge.config().display.limits.runs),
  }
  if branch then
    table.insert(cmd, '--ref')
    table.insert(cmd, branch)
  end
  return cmd
end

function M:normalize_run(entry)
  local ref = entry.ref or ''
  local mr_num = ref:match('^refs/merge%-requests/(%d+)/head$')
  return {
    id = tostring(entry.id or ''),
    name = mr_num and ('!%s'):format(mr_num) or ref,
    branch = '',
    status = entry.status or '',
    event = entry.source or '',
    url = entry.web_url or '',
    created_at = entry.created_at or '',
  }
end

function M:run_log_cmd(id, failed_only)
  local lines = forge.config().ci.lines
  local jq_filter = failed_only and '[.[] | select(.status=="failed")][0].id // .[0].id'
    or '.[0].id'
  return {
    'sh',
    '-c',
    ('JOB=$(glab api \'projects/:id/pipelines/%s/jobs?per_page=100\' | jq -r \'%s\') && [ "$JOB" != "null" ] && glab ci trace "$JOB" | tail -n %d'):format(
      id,
      jq_filter,
      lines
    ),
  }
end

function M:run_tail_cmd(id)
  local jq_filter = '[.[] | select(.status=="running" or .status=="pending")][0].id // .[0].id'
  return {
    'sh',
    '-c',
    ('JOB=$(glab api \'projects/:id/pipelines/%s/jobs?per_page=100\' | jq -r \'%s\') && [ "$JOB" != "null" ] && glab ci trace "$JOB"'):format(
      id,
      jq_filter
    ),
  }
end

---@param num string
---@param method string
---@return string[]
function M:merge_cmd(num, method)
  local cmd = { 'glab', 'mr', 'merge', num }
  if method == 'squash' then
    table.insert(cmd, '--squash')
  elseif method == 'rebase' then
    table.insert(cmd, '--rebase')
  end
  return cmd
end

---@param num string
---@return string[]
function M:approve_cmd(num)
  return { 'glab', 'mr', 'approve', num }
end

---@param num string
---@return string[]
function M:close_cmd(num)
  return { 'glab', 'mr', 'close', num }
end

---@param num string
---@return string[]
function M:reopen_cmd(num)
  return { 'glab', 'mr', 'reopen', num }
end

---@param num string
---@return string[]
function M:close_issue_cmd(num)
  return { 'glab', 'issue', 'close', num }
end

---@param num string
---@return string[]
function M:reopen_issue_cmd(num)
  return { 'glab', 'issue', 'reopen', num }
end

---@param num string
---@return string[]
function M:fetch_pr_details_cmd(num)
  return { 'glab', 'mr', 'view', num, '--output', 'json' }
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
  local cmd = { 'glab', 'mr', 'update', num, '--title', title, '--description', body }
  for _, r in ipairs(reviewers or {}) do
    table.insert(cmd, '--reviewer')
    table.insert(cmd, r)
  end
  if labels and #labels > 0 then
    table.insert(cmd, '--label')
    table.insert(cmd, table.concat(labels, ','))
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

---@param json table
---@return { title: string, body: string, draft: boolean, reviewers: string[], labels: string[], assignees: string[], milestone: string }
function M:parse_pr_details(json)
  local labels = {}
  for _, l in ipairs(json.labels or {}) do
    table.insert(labels, type(l) == 'string' and l or '')
  end
  local assignees = {}
  for _, a in ipairs(json.assignees or {}) do
    table.insert(assignees, a.username or '')
  end
  local reviewers = {}
  for _, r in ipairs(json.reviewers or {}) do
    table.insert(reviewers, r.username or '')
  end
  local milestone = ''
  if type(json.milestone) == 'table' and json.milestone.title then
    milestone = json.milestone.title
  end
  return {
    title = json.title or '',
    body = json.description or '',
    draft = json.draft == true,
    labels = labels,
    assignees = assignees,
    reviewers = reviewers,
    milestone = milestone,
  }
end

---@param field string
---@return string[]?
function M:completion_cmd(field)
  if field == 'labels' then
    return { 'sh', '-c', "glab label list -F json | jq -r '.[].name'" }
  elseif field == 'assignees' or field == 'reviewers' or field == 'mentions' then
    return { 'sh', '-c', "glab api 'projects/:id/members/all?per_page=100' | jq -r '.[].username'" }
  elseif field == 'milestone' then
    return { 'sh', '-c', "glab api 'projects/:id/milestones?state=active' | jq -r '.[].title'" }
  elseif field == 'issues' then
    return {
      'sh',
      '-c',
      'glab issue list --per-page 50 -F json | jq -r \'.[] | "\\(.iid)\\t\\(.title)"\''
        .. ' && glab mr list --per-page 50 -F json | jq -r \'.[] | "\\(.iid)\\t\\(.title)"\'',
    }
  end
  return nil
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
  local cmd = {
    'glab',
    'mr',
    'create',
    '--title',
    title,
    '--description',
    body,
    '--target-branch',
    base,
    '--yes',
  }
  if draft then
    table.insert(cmd, '--draft')
  end
  for _, r in ipairs(reviewers or {}) do
    table.insert(cmd, '--reviewer')
    table.insert(cmd, r)
  end
  if labels and #labels > 0 then
    table.insert(cmd, '--label')
    table.insert(cmd, table.concat(labels, ','))
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
  return { 'glab', 'mr', 'create', '--web' }
end

---@param title string
---@param body string
---@param labels string[]?
---@param assignees string[]?
---@param milestone string?
---@return string[]
function M:create_issue_cmd(title, body, labels, assignees, milestone)
  local cmd = { 'glab', 'issue', 'create', '--title', title, '--description', body, '--yes' }
  if labels and #labels > 0 then
    table.insert(cmd, '--label')
    table.insert(cmd, table.concat(labels, ','))
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
  return { 'glab', 'issue', 'create', '--web' }
end

---@return string[]
function M:issue_template_paths()
  return { '.gitlab/issue_templates/' }
end

---@return string[]
function M:default_branch_cmd()
  return {
    'sh',
    '-c',
    "glab repo view -F json | jq -r '.default_branch'",
  }
end

---@return string[]
function M:template_paths()
  return { '.gitlab/merge_request_templates/' }
end

---@param num string
---@param is_draft boolean
---@return string[]?
function M:draft_toggle_cmd(num, is_draft)
  if is_draft then
    return { 'glab', 'mr', 'update', num, '--ready' }
  end
  return { 'glab', 'mr', 'update', num, '--draft' }
end

---@return forge.RepoInfo
function M:repo_info()
  local result = vim.system({ 'glab', 'api', 'projects/:id' }, { text = true }):wait()
  local ok, data = pcall(vim.json.decode, result.stdout or '{}')
  if not ok or type(data) ~= 'table' then
    data = {}
  end
  local perms = type(data.permissions) == 'table' and data.permissions or {}
  local pa = type(perms.project_access) == 'table' and perms.project_access or {}
  local ga = type(perms.group_access) == 'table' and perms.group_access or {}
  local access = pa.access_level or 0
  local group_access = ga.access_level or 0
  local level = math.max(access, group_access)

  local permission = 'READ'
  if level >= 40 then
    permission = 'ADMIN'
  elseif level >= 30 then
    permission = 'WRITE'
  end

  local methods = {}
  local merge_method = data.merge_method or 'merge'
  if merge_method == 'ff' or merge_method == 'rebase_merge' then
    table.insert(methods, 'rebase')
  else
    table.insert(methods, 'merge')
  end
  if data.squash_option ~= 'never' then
    table.insert(methods, 'squash')
  end

  return {
    permission = permission,
    merge_methods = methods,
  }
end

---@param num string
---@return forge.PRState
function M:pr_state(num)
  local result = vim
    .system({ 'glab', 'mr', 'view', num, '--output', 'json' }, { text = true })
    :wait()
  local ok, data = pcall(vim.json.decode, result.stdout or '{}')
  if not ok or type(data) ~= 'table' then
    data = {}
  end
  return {
    state = (data.state or 'unknown'):upper(),
    mergeable = data.merge_status or 'unknown',
    review_decision = '',
    is_draft = data.draft == true,
  }
end

function M:list_releases_json_cmd()
  return { 'glab', 'release', 'list', '--output', 'json' }
end

---@param tag string
function M:browse_release(tag)
  local base = forge.remote_web_url()
  vim.ui.open(base .. '/-/releases/' .. tag)
end

---@param tag string
---@return string[]
function M:delete_release_cmd(tag)
  return { 'glab', 'release', 'delete', tag }
end

return M
