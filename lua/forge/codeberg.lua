local forge = require('forge')

---@class forge.Codeberg: forge.Forge
local M = {
  name = 'codeberg',
  cli = 'tea',
  kinds = { issue = 'issues', pr = 'pulls' },
  labels = {
    issue = 'Issues',
    pr = 'PRs',
    pr_one = 'PR',
    pr_full = 'Pull Requests',
    ci = 'CI/CD',
  },
  capabilities = {
    draft = false,
    per_pr_checks = true,
    ci_json = true,
  },
  pr_fields = {
    number = 'index',
    title = 'title',
    branch = 'head',
    state = 'state',
    author = 'poster',
    created_at = 'created_at',
  },
  issue_fields = {
    number = 'index',
    title = 'title',
    state = 'state',
    author = 'poster',
    created_at = 'created_at',
  },
  release_fields = {
    tag = 'tag_name',
    title = 'name',
    is_draft = 'draft',
    is_prerelease = 'prerelease',
    published_at = 'published_at',
  },
}

local function repo_arg(ref)
  local current = ref or forge.current_scope(M.name)
  return forge.scope_repo_arg(current) or ''
end

---@param state string
---@param limit integer?
---@return string[]
function M:list_pr_json_cmd(state, limit, ref)
  return {
    'tea',
    'pulls',
    'list',
    '--state',
    state,
    '--limit',
    tostring(limit or forge.config().display.limits.pulls),
    '--output',
    'json',
    '--fields',
    'index,title,head,state,poster,created_at',
    '--repo',
    repo_arg(ref),
  }
end

---@param state string
---@param limit integer?
---@return string[]
function M:list_issue_json_cmd(state, limit, ref)
  return {
    'tea',
    'issues',
    'list',
    '--state',
    state,
    '--limit',
    tostring(limit or forge.config().display.limits.issues),
    '--output',
    'json',
    '--fields',
    'index,title,state,poster,created_at',
    '--repo',
    repo_arg(ref),
  }
end

---@param kind string
---@param num string
function M:view_web(kind, num, ref)
  local base = forge.remote_web_url(ref)
  vim.ui.open(('%s/%s/%s'):format(base, kind, num))
end

---@param loc string
---@param branch string
function M:browse(loc, branch, ref)
  local base = forge.remote_web_url(ref)
  local file, lines = loc:match('^(.+):(.+)$')
  vim.ui.open(('%s/src/branch/%s/%s#L%s'):format(base, branch, file, lines))
end

function M:browse_branch(branch, ref)
  local base = forge.remote_web_url(ref)
  vim.ui.open(base .. '/src/branch/' .. branch)
end

function M:browse_commit(sha, ref)
  local base = forge.remote_web_url(ref)
  vim.ui.open(base .. '/commit/' .. sha)
end

function M:checkout_cmd(num, ref)
  return { 'tea', 'pr', 'checkout', num, '--repo', repo_arg(ref) }
end

---@param num string
---@return string[]
function M:fetch_pr(num)
  return { 'git', 'fetch', 'origin', ('pull/%s/head:pr-%s'):format(num, num) }
end

---@param num string
---@return string[]
function M:pr_base_cmd(num, ref)
  return { 'tea', 'pr', num, '--fields', 'base', '--output', 'simple', '--repo', repo_arg(ref) }
end

---@param branch string
---@return string[]
function M:pr_for_branch_cmd(branch, ref)
  return {
    'sh',
    '-c',
    ('tea pr list --state open --output json --fields index,head --repo %s | jq -r \'[.[] | select(.head=="%s" or .head.name=="%s")][0].index // empty\''):format(
      repo_arg(ref),
      branch,
      branch
    ),
  }
end

---@param num string
---@return string[]
function M:checks_json_cmd(num, ref)
  local jq = [=[
    [.statuses // [] | .[] | {
      name: .context,
      bucket: (if .status == "success" then "pass"
               elif (.status == "failure" or .status == "error") then "fail"
               elif .status == "pending" then "pending"
               else "skipping" end),
      link: .target_url,
      startedAt: .created_at,
      completedAt: .updated_at
    }]
  ]=]
  return {
    'sh',
    '-c',
    ('SHA=$(tea api --repo %s "/repos/{owner}/{repo}/pulls/%s" 2>/dev/null | jq -r ".head.sha // empty") && [ -n "$SHA" ] && tea api --repo %s "/repos/{owner}/{repo}/commits/$SHA/status" 2>/dev/null | jq -r \'%s\''):format(
      repo_arg(ref),
      num,
      repo_arg(ref),
      jq:gsub('%s+', ' ')
    ),
  }
end

---@param num string
---@return string
function M:checks_cmd(num)
  local _ = num
  return 'tea actions runs list'
end

---@param run_id string
---@param failed_only boolean
---@param job_id string?
---@return string[]
function M:check_log_cmd(run_id, failed_only, job_id, ref)
  local _ = failed_only
  local lines = forge.config().ci.lines
  local job_flag = job_id and (' --job %s'):format(job_id) or ''
  return {
    'sh',
    '-c',
    ('tea actions runs logs %s --repo %s%s | tail -n %d'):format(
      run_id,
      repo_arg(ref),
      job_flag,
      lines
    ),
  }
end

---@param run_id string
---@return string[]
function M:check_tail_cmd(run_id, ref)
  return { 'tea', 'actions', 'runs', 'logs', run_id, '--follow', '--repo', repo_arg(ref) }
end

---@param run_id string
---@param job_id string?
---@return string[]
function M:live_tail_cmd(run_id, job_id, ref)
  local cmd = { 'tea', 'actions', 'runs', 'logs', run_id, '--follow', '--repo', repo_arg(ref) }
  if job_id then
    table.insert(cmd, '--job')
    table.insert(cmd, job_id)
  end
  return cmd
end

function M:list_runs_json_cmd(branch, ref, limit)
  local limit_arg = tostring(limit or forge.config().display.limits.runs)
  local cmd = 'tea api --repo '
    .. repo_arg(ref)
    .. ' "/repos/{owner}/{repo}/actions/runs?limit='
    .. limit_arg
  if branch then
    cmd = cmd .. '&branch=' .. branch
  end
  cmd = cmd .. '" 2>/dev/null | jq -r ".workflow_runs // []"'
  return { 'sh', '-c', cmd }
end

function M:normalize_run(entry)
  local status = entry.status or ''
  if status == 'completed' then
    status = entry.conclusion or 'unknown'
  end
  return {
    id = tostring(entry.id or ''),
    name = entry.name or '',
    branch = entry.head_branch or '',
    status = status,
    event = entry.event or '',
    url = entry.html_url or '',
    created_at = entry.created_at or '',
  }
end

function M:run_log_cmd(id, failed_only, ref)
  local _ = failed_only
  local lines = forge.config().ci.lines
  return {
    'sh',
    '-c',
    ('tea actions runs logs %s --repo %s | tail -n %d'):format(id, repo_arg(ref), lines),
  }
end

function M:run_tail_cmd(id, ref)
  return { 'tea', 'actions', 'runs', 'logs', id, '--follow', '--repo', repo_arg(ref) }
end

---@param num string
---@param method string
---@return string[]
function M:merge_cmd(num, method, ref)
  local cmd = { 'tea', 'pr', 'merge', num }
  if method and method ~= '' then
    table.insert(cmd, '--style')
    table.insert(cmd, method)
  end
  table.insert(cmd, '--repo')
  table.insert(cmd, repo_arg(ref))
  return cmd
end

---@param num string
---@return string[]
function M:approve_cmd(num, ref)
  return { 'tea', 'pr', 'approve', num, '--repo', repo_arg(ref) }
end

---@param num string
---@return string[]
function M:close_cmd(num, ref)
  return { 'tea', 'pulls', 'close', num, '--repo', repo_arg(ref) }
end

---@param num string
---@return string[]
function M:reopen_cmd(num, ref)
  return { 'tea', 'pulls', 'reopen', num, '--repo', repo_arg(ref) }
end

---@param num string
---@return string[]
function M:close_issue_cmd(num, ref)
  return { 'tea', 'issues', 'close', num, '--repo', repo_arg(ref) }
end

---@param num string
---@return string[]
function M:reopen_issue_cmd(num, ref)
  return { 'tea', 'issues', 'reopen', num, '--repo', repo_arg(ref) }
end

---@param num string
---@return string[]
function M:fetch_pr_details_cmd(num, ref)
  return {
    'sh',
    '-c',
    ('tea api --repo %s "/repos/{owner}/{repo}/pulls/%s"'):format(repo_arg(ref), num),
  }
end

function M:fetch_issue_details_cmd(num, ref)
  return {
    'sh',
    '-c',
    ('tea api --repo %s "/repos/{owner}/{repo}/issues/%s"'):format(repo_arg(ref), num),
  }
end

---@param num string
---@param title string
---@param body string
---@return string[]
function M:update_pr_cmd(num, title, body, ref)
  return {
    'tea',
    'pr',
    'edit',
    num,
    '--title',
    title,
    '--description',
    body,
    '--repo',
    repo_arg(ref),
  }
end

function M:update_issue_cmd(num, title, body, ref)
  local cmd = {
    'tea',
    'issues',
    'edit',
    num,
    '--title',
    title,
    '--description',
    body,
    '--repo',
    repo_arg(ref),
  }
  return cmd
end

---@param json table
---@return forge.PRDetails
function M:parse_pr_details(json)
  return {
    title = json.title or '',
    body = json.body or '',
    head_branch = type(json.head) == 'table' and (json.head.ref or '') or json.head or '',
    base_branch = type(json.base) == 'table' and (json.base.ref or '') or json.base or '',
  }
end

function M:parse_issue_details(json)
  return {
    title = json.title or '',
    body = json.body or '',
  }
end

---@param field string
---@return string[]?
function M:completion_cmd(field, ref)
  if field == 'mentions' then
    return {
      'sh',
      '-c',
      'tea api --repo '
        .. repo_arg(ref)
        .. " '/repos/{owner}/{repo}/collaborators' | jq -r '.[].login'",
    }
  elseif field == 'issues' then
    return {
      'sh',
      '-c',
      'tea api --repo '
        .. repo_arg(ref)
        .. " '/repos/{owner}/{repo}/issues?limit=50&type=issues' | jq -r '.[] | \"\\(.number)\\t\\(.title)\"'"
        .. ' && tea api --repo '
        .. repo_arg(ref)
        .. " '/repos/{owner}/{repo}/pulls?limit=50' | jq -r '.[] | \"\\(.number)\\t\\(.title)\"'",
    }
  end
  return nil
end

---@param title string
---@param body string
---@param base string
---@param _draft boolean
---@return string[]
function M:create_pr_cmd(title, body, base, _draft, ref)
  local cmd = {
    'tea',
    'pr',
    'create',
    '--title',
    title,
    '--description',
    body,
    '--base',
    base,
    '--repo',
    repo_arg(ref),
  }
  return cmd
end

---@return string
function M:create_pr_web_url(ref, _, head_branch, base_branch)
  local branch = head_branch or vim.trim(vim.fn.system('git branch --show-current'))
  local base_url = forge.remote_web_url(ref)
  local default = base_branch
  if not default or default == '' then
    default = vim.trim(
      vim.fn.system(
        "git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'"
      )
    )
    if default == '' then
      default = 'main'
    end
  end
  return ('%s/compare/%s...%s'):format(base_url, default, branch)
end

---@param title string
---@param body string
---@param labels string[]?
---@param assignees string[]?
---@param milestone string?
---@return string[]
function M:create_issue_cmd(title, body, labels, ref)
  local cmd =
    { 'tea', 'issues', 'create', '--title', title, '--description', body, '--repo', repo_arg(ref) }
  if labels and #labels > 0 then
    table.insert(cmd, '--labels')
    table.insert(cmd, table.concat(labels, ','))
  end
  return cmd
end

---@return string[]
function M:issue_template_paths()
  return {
    '.gitea/issue_template.md',
    '.gitea/ISSUE_TEMPLATE/',
    '.github/ISSUE_TEMPLATE.md',
    '.github/ISSUE_TEMPLATE/',
  }
end

---@return string[]
function M:default_branch_cmd(ref)
  return {
    'sh',
    '-c',
    "git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'"
      .. ' || tea api --repo '
      .. repo_arg(ref)
      .. " /repos/{owner}/{repo} 2>/dev/null | jq -r '.default_branch // empty'",
  }
end

---@return string[]
function M:template_paths()
  return {
    '.gitea/pull_request_template.md',
    '.github/pull_request_template.md',
    '.github/PULL_REQUEST_TEMPLATE.md',
  }
end

---@param _num string
---@param _is_draft boolean
---@return string[]?
function M:draft_toggle_cmd(_num, _is_draft)
  return nil
end

---@return forge.RepoInfo
function M:repo_info(ref)
  local result = vim
    .system({ 'tea', 'api', '--repo', repo_arg(ref), '/repos/{owner}/{repo}' }, { text = true })
    :wait()
  local ok, data = pcall(vim.json.decode, result.stdout or '{}')
  if not ok or type(data) ~= 'table' then
    return { permission = 'READ', merge_methods = { 'merge' } }
  end

  local perms = type(data.permissions) == 'table' and data.permissions or {}
  local permission = 'READ'
  if perms.admin then
    permission = 'ADMIN'
  elseif perms.push then
    permission = 'WRITE'
  end

  local methods = {}
  if data.allow_merge_commits ~= false then
    table.insert(methods, 'merge')
  end
  if data.allow_squash_merge ~= false then
    table.insert(methods, 'squash')
  end
  if data.allow_rebase ~= false then
    table.insert(methods, 'rebase')
  end
  if #methods == 0 then
    table.insert(methods, 'merge')
  end

  return { permission = permission, merge_methods = methods }
end

---@param num string
---@return forge.PRState
function M:pr_state(num, ref)
  local result = vim
    .system({
      'tea',
      'pr',
      num,
      '--fields',
      'state,mergeable',
      '--output',
      'json',
      '--repo',
      repo_arg(ref),
    }, { text = true })
    :wait()
  local ok, data = pcall(vim.json.decode, result.stdout or '{}')
  if not ok or type(data) ~= 'table' then
    data = {}
  end
  return {
    state = (data.state or 'unknown'):upper(),
    mergeable = data.mergeable and 'MERGEABLE' or 'UNKNOWN',
    review_decision = '',
    is_draft = false,
  }
end

function M:list_releases_json_cmd(ref)
  local limit = tostring(forge.config().display.limits.releases)
  return {
    'sh',
    '-c',
    'tea releases list --limit ' .. limit .. ' --output json --repo ' .. repo_arg(ref),
  }
end

---@param tag string
function M:browse_release(tag, ref)
  local base = forge.remote_web_url(ref)
  vim.ui.open(base .. '/releases/tag/' .. tag)
end

---@param tag string
---@return string[]
function M:delete_release_cmd(tag, ref)
  return {
    'sh',
    '-c',
    'tea releases delete --confirm --repo ' .. repo_arg(ref) .. ' ' .. tag,
  }
end

return M
