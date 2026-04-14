local forge = require('forge')
local scope = require('forge.scope')
local submission = require('forge.submission')

---@class forge.GitLab: forge.Forge
local M = {
  name = 'gitlab',
  cli = 'glab',
  kinds = { issue = 'issue', pr = 'mr' },
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

local function repo_arg(ref)
  return forge.scope_repo_arg(ref) or forge.remote_web_url()
end

local function project(ref)
  local current = ref or forge.current_scope(M.name)
  return scope.encode_project(current) or ''
end

local function hostname(ref)
  local current = ref or forge.current_scope(M.name)
  return current and current.host or nil
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
function M:list_pr_json_cmd(state, limit, ref)
  local cmd = {
    'glab',
    'mr',
    'list',
    '--per-page',
    tostring(limit or forge.config().display.limits.pulls),
    '--output',
    'json',
  }
  local repo = repo_arg(ref)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  if state == 'closed' then
    table.insert(cmd, '--closed')
  elseif state == 'all' then
    table.insert(cmd, '--all')
  end
  return cmd
end

---@param state string
---@param limit integer?
---@return string[]
function M:list_issue_json_cmd(state, limit, ref)
  local cmd = {
    'glab',
    'issue',
    'list',
    '--per-page',
    tostring(limit or forge.config().display.limits.issues),
    '--output',
    'json',
  }
  local repo = repo_arg(ref)
  if repo ~= '' then
    table.insert(cmd, '-R')
    table.insert(cmd, repo)
  end
  if state == 'closed' then
    table.insert(cmd, '--closed')
  elseif state == 'all' then
    table.insert(cmd, '--all')
  end
  return cmd
end

---@param kind string
---@param num string
function M:view_web(kind, num, ref)
  vim.system({ 'glab', kind, 'view', num, '--web', '-R', repo_arg(ref) })
end

---@param loc string
---@param branch string
function M:browse(loc, branch, ref)
  local base = forge.remote_web_url(ref)
  local file, lines = loc:match('^(.+):(.+)$')
  vim.ui.open(('%s/-/blob/%s/%s#L%s'):format(base, branch, file, lines))
end

function M:browse_branch(branch, ref)
  local base = forge.remote_web_url(ref)
  vim.ui.open(base .. '/-/tree/' .. branch)
end

function M:browse_commit(sha, ref)
  local base = forge.remote_web_url(ref)
  vim.ui.open(base .. '/-/commit/' .. sha)
end

function M:checkout_cmd(num, ref)
  return { 'glab', 'mr', 'checkout', num, '-R', repo_arg(ref) }
end

---@param num string
---@return string[]
function M:fetch_pr(num, ref)
  local remote = 'origin'
  local current = forge.current_scope(M.name)
  if ref and forge.scope_key(ref) ~= '' and forge.scope_key(ref) ~= forge.scope_key(current) then
    remote = forge.remote_web_url(ref) .. '.git'
  end
  return {
    'git',
    'fetch',
    remote,
    ('merge-requests/%s/head:mr-%s'):format(num, num),
  }
end

---@param num string
---@return string[]
function M:pr_base_cmd(num, ref)
  return {
    'sh',
    '-c',
    ("glab mr view %s -F json -R '%s' | jq -r .target_branch"):format(num, repo_arg(ref)),
  }
end

---@param branch string
---@return string[]
function M:pr_for_branch_cmd(branch, ref)
  return {
    'sh',
    '-c',
    ("glab mr list --source-branch '%s' -F json -R '%s' | jq -r '.[0].iid // empty'"):format(
      branch,
      repo_arg(ref)
    ),
  }
end

---@param num string
---@return string[]
function M:checks_json_cmd(num, ref)
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
    ('PID=$(glab api --hostname %s "projects/%s/merge_requests/%s/pipelines?per_page=1" 2>/dev/null | jq -r ".[0].id // empty") && [ -n "$PID" ] && glab api --hostname %s "projects/%s/pipelines/$PID/jobs?per_page=100" 2>/dev/null | jq -r \'%s\''):format(
      hostname(ref) or 'gitlab.com',
      project(ref),
      num,
      hostname(ref) or 'gitlab.com',
      project(ref),
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
function M:check_log_cmd(run_id, failed_only, job_id, ref)
  local _ = failed_only
  local lines = forge.config().ci.lines
  local id = job_id or run_id
  return {
    'sh',
    '-c',
    ("glab ci trace %s -R '%s' | tail -n %d"):format(id, repo_arg(ref), lines),
  }
end

---@param run_id string
---@return string[]
function M:check_tail_cmd(run_id, ref)
  return { 'glab', 'ci', 'trace', run_id, '-R', repo_arg(ref) }
end

---@param run_id string
---@return string[]
function M:live_tail_cmd(run_id, _, ref)
  return { 'glab', 'ci', 'trace', run_id, '-R', repo_arg(ref) }
end

---@param id string?
---@return string[]
function M:watch_cmd(id, ref)
  local cmd = { 'glab', 'ci', 'view' }
  table.insert(cmd, '-R')
  table.insert(cmd, repo_arg(ref))
  if id then
    table.insert(cmd, '-p')
    table.insert(cmd, id)
  end
  return cmd
end

function M:list_runs_json_cmd(branch, ref, limit)
  local cmd = {
    'glab',
    'ci',
    'list',
    '--output',
    'json',
    '--per-page',
    tostring(limit or forge.config().display.limits.runs),
    '-R',
    repo_arg(ref),
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

function M:run_log_cmd(id, failed_only, ref)
  local lines = forge.config().ci.lines
  local jq_filter = failed_only and '[.[] | select(.status=="failed")][0].id // .[0].id'
    or '.[0].id'
  return {
    'sh',
    '-c',
    ('JOB=$(glab api --hostname %s \'projects/%s/pipelines/%s/jobs?per_page=100\' | jq -r \'%s\') && [ "$JOB" != "null" ] && glab ci trace "$JOB" -R \'%s\' | tail -n %d'):format(
      hostname(ref) or 'gitlab.com',
      project(ref),
      id,
      jq_filter,
      repo_arg(ref),
      lines
    ),
  }
end

function M:run_tail_cmd(id, ref)
  local jq_filter = '[.[] | select(.status=="running" or .status=="pending")][0].id // .[0].id'
  return {
    'sh',
    '-c',
    ('JOB=$(glab api --hostname %s \'projects/%s/pipelines/%s/jobs?per_page=100\' | jq -r \'%s\') && [ "$JOB" != "null" ] && glab ci trace "$JOB" -R \'%s\''):format(
      hostname(ref) or 'gitlab.com',
      project(ref),
      id,
      jq_filter,
      repo_arg(ref)
    ),
  }
end

---@param num string
---@param method string
---@return string[]
function M:merge_cmd(num, method, ref)
  local cmd = { 'glab', 'mr', 'merge', num }
  table.insert(cmd, '-R')
  table.insert(cmd, repo_arg(ref))
  if method == 'squash' then
    table.insert(cmd, '--squash')
  elseif method == 'rebase' then
    table.insert(cmd, '--rebase')
  end
  return cmd
end

---@param num string
---@return string[]
function M:approve_cmd(num, ref)
  return { 'glab', 'mr', 'approve', num, '-R', repo_arg(ref) }
end

---@param num string
---@return string[]
function M:close_cmd(num, ref)
  return { 'glab', 'mr', 'close', num, '-R', repo_arg(ref) }
end

---@param num string
---@return string[]
function M:reopen_cmd(num, ref)
  return { 'glab', 'mr', 'reopen', num, '-R', repo_arg(ref) }
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
function M:fetch_pr_details_cmd(num, ref)
  return { 'glab', 'mr', 'view', num, '--output', 'json', '-R', repo_arg(ref) }
end

function M:fetch_issue_details_cmd(num, ref)
  return { 'glab', 'issue', 'view', num, '--output', 'json', '-R', repo_arg(ref) }
end

---@param num string
---@param title string
---@param body string
---@return string[]
function M:update_pr_cmd(num, title, body, ref, metadata, previous)
  local cmd =
    { 'glab', 'mr', 'update', num, '--title', title, '--description', body, '-R', repo_arg(ref) }
  local current = submission.filter(self, 'pr', 'update', metadata)
  local before = previous or { labels = {}, assignees = {}, reviewers = {}, milestone = '' }
  local add_labels, remove_labels = submission.diff(before.labels, current.labels)
  append_csv(cmd, '--label', add_labels)
  append_csv(cmd, '--unlabel', remove_labels)
  if
    current.assignees ~= nil
    and vim.deep_equal(current.assignees, before.assignees or {}) == false
  then
    if #current.assignees == 0 then
      table.insert(cmd, '--unassign')
    else
      append_csv(cmd, '--assignee', current.assignees)
    end
  end
  if
    current.reviewers ~= nil
    and vim.deep_equal(current.reviewers, before.reviewers or {}) == false
  then
    if #current.reviewers == 0 then
      local removed = {}
      for _, reviewer in ipairs(before.reviewers or {}) do
        table.insert(removed, '-' .. reviewer)
      end
      append_csv(cmd, '--reviewer', removed)
    else
      append_csv(cmd, '--reviewer', current.reviewers)
    end
  end
  if current.milestone ~= (before.milestone or '') then
    table.insert(cmd, '--milestone')
    table.insert(cmd, current.milestone ~= '' and current.milestone or '0')
  end
  return cmd
end

function M:update_issue_cmd(num, title, body, ref, metadata, previous)
  local cmd = {
    'glab',
    'issue',
    'update',
    num,
    '--title',
    title,
    '--description',
    body,
    '-R',
    repo_arg(ref),
  }
  local current = submission.filter(self, 'issue', 'update', metadata)
  local before = previous or { labels = {}, assignees = {}, milestone = '' }
  local add_labels, remove_labels = submission.diff(before.labels, current.labels)
  append_csv(cmd, '--label', add_labels)
  append_csv(cmd, '--unlabel', remove_labels)
  if
    current.assignees ~= nil
    and vim.deep_equal(current.assignees, before.assignees or {}) == false
  then
    if #current.assignees == 0 then
      table.insert(cmd, '--unassign')
    else
      append_csv(cmd, '--assignee', current.assignees)
    end
  end
  if current.milestone ~= (before.milestone or '') then
    table.insert(cmd, '--milestone')
    table.insert(cmd, current.milestone ~= '' and current.milestone or '0')
  end
  return cmd
end

---@param json table
---@return forge.PRDetails
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
    head_branch = json.source_branch or '',
    base_branch = json.target_branch or '',
    labels = labels,
    assignees = assignees,
    reviewers = reviewers,
    milestone = milestone,
  }
end

function M:parse_issue_details(json)
  local labels = {}
  for _, l in ipairs(json.labels or {}) do
    table.insert(labels, type(l) == 'string' and l or '')
  end
  local assignees = {}
  for _, a in ipairs(json.assignees or {}) do
    table.insert(assignees, a.username or '')
  end
  local milestone = ''
  if type(json.milestone) == 'table' and json.milestone.title then
    milestone = json.milestone.title
  end
  return {
    title = json.title or '',
    body = json.description or '',
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
function M:create_pr_cmd(title, body, base, draft, ref, metadata)
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
    '-R',
    repo_arg(ref),
  }
  local current = metadata and submission.filter(self, 'pr', 'create', metadata) or nil
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
function M:create_pr_web_cmd(ref, head_scope, head_branch, base_branch)
  local cmd = { 'glab', 'mr', 'create', '--web', '-R', repo_arg(ref) }
  if
    head_scope
    and forge.scope_key(head_scope) ~= ''
    and forge.scope_key(head_scope) ~= forge.scope_key(ref)
  then
    table.insert(cmd, '--head')
    table.insert(cmd, repo_arg(head_scope))
  end
  if head_branch and head_branch ~= '' then
    table.insert(cmd, '--source-branch')
    table.insert(cmd, head_branch)
  end
  if base_branch and base_branch ~= '' then
    table.insert(cmd, '--target-branch')
    table.insert(cmd, base_branch)
  end
  return cmd
end

---@param title string
---@param body string
---@param labels string[]?
---@return string[]
function M:create_issue_cmd(title, body, labels, ref, metadata)
  local cmd = {
    'glab',
    'issue',
    'create',
    '--title',
    title,
    '--description',
    body,
    '--yes',
    '-R',
    repo_arg(ref),
  }
  local current = metadata and submission.filter(self, 'issue', 'create', metadata) or nil
  local effective_labels = current and current.labels or labels or {}
  append_csv(cmd, '--label', effective_labels)
  append_csv(cmd, '--assignee', current and current.assignees or {})
  if current and current.milestone ~= '' then
    table.insert(cmd, '--milestone')
    table.insert(cmd, current.milestone)
  end
  return cmd
end

---@return string[]
function M:create_issue_web_cmd(ref)
  return { 'glab', 'issue', 'create', '--web', '-R', repo_arg(ref) }
end

---@return string[]
function M:issue_template_paths()
  return { '.gitlab/issue_templates/' }
end

---@return string[]
function M:default_branch_cmd(ref)
  return {
    'sh',
    '-c',
    "glab repo view -F json -R '" .. repo_arg(ref) .. "' | jq -r '.default_branch'",
  }
end

---@return string[]
function M:template_paths()
  return { '.gitlab/merge_request_templates/' }
end

---@param num string
---@param is_draft boolean
---@return string[]?
function M:draft_toggle_cmd(num, is_draft, ref)
  if is_draft then
    return { 'glab', 'mr', 'update', num, '--ready', '-R', repo_arg(ref) }
  end
  return { 'glab', 'mr', 'update', num, '--draft', '-R', repo_arg(ref) }
end

---@return forge.RepoInfo
function M:repo_info(ref)
  local result = vim
    .system({
      'glab',
      'api',
      '--hostname',
      hostname(ref) or 'gitlab.com',
      'projects/' .. project(ref),
    }, { text = true })
    :wait()
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
function M:pr_state(num, ref)
  local result = vim
    .system({ 'glab', 'mr', 'view', num, '--output', 'json', '-R', repo_arg(ref) }, { text = true })
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

function M:list_releases_json_cmd(ref, limit)
  return {
    'glab',
    'release',
    'list',
    '--output',
    'json',
    '--per-page',
    tostring(limit or forge.config().display.limits.releases),
    '-R',
    repo_arg(ref),
  }
end

---@param tag string
function M:browse_release(tag, ref)
  local base = forge.remote_web_url(ref)
  vim.ui.open(base .. '/-/releases/' .. tag)
end

---@param tag string
---@return string[]
function M:delete_release_cmd(tag, ref)
  return { 'glab', 'release', 'delete', tag, '-R', repo_arg(ref) }
end

return M
