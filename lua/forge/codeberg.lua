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
    reviewers = false,
    per_pr_checks = true,
    ci_json = true,
  },
}

---@param state string
---@return string[]
function M:list_pr_json_cmd(state)
  return {
    'tea',
    'pulls',
    'list',
    '--state',
    state,
    '--output',
    'json',
    '--fields',
    'index,title,head,state,poster,created_at',
  }
end

---@param state string
---@return string[]
function M:list_issue_json_cmd(state)
  return {
    'tea',
    'issues',
    'list',
    '--state',
    state,
    '--output',
    'json',
    '--fields',
    'index,title,state,poster,created_at',
  }
end

function M:pr_json_fields()
  return {
    number = 'index',
    title = 'title',
    branch = 'head',
    state = 'state',
    author = 'poster',
    created_at = 'created_at',
  }
end

function M:issue_json_fields()
  return {
    number = 'index',
    title = 'title',
    state = 'state',
    author = 'poster',
    created_at = 'created_at',
  }
end

---@param kind string
---@param num string
function M:view_web(kind, num)
  local base = forge.remote_web_url()
  vim.ui.open(('%s/%s/%s'):format(base, kind, num))
end

---@param loc string
---@param branch string
function M:browse(loc, branch)
  local base = forge.remote_web_url()
  local file, lines = loc:match('^(.+):(.+)$')
  vim.ui.open(('%s/src/branch/%s/%s#L%s'):format(base, branch, file, lines))
end

function M:browse_branch(branch)
  local base = forge.remote_web_url()
  vim.ui.open(base .. '/src/branch/' .. branch)
end

function M:browse_commit(sha)
  local base = forge.remote_web_url()
  vim.ui.open(base .. '/commit/' .. sha)
end

function M:checkout_cmd(num)
  return { 'tea', 'pr', 'checkout', num }
end

---@param num string
---@return string[]
function M:fetch_pr(num)
  return { 'git', 'fetch', 'origin', ('pull/%s/head:pr-%s'):format(num, num) }
end

---@param num string
---@return string[]
function M:pr_base_cmd(num)
  return { 'tea', 'pr', num, '--fields', 'base', '--output', 'simple' }
end

---@param branch string
---@return string[]
function M:pr_for_branch_cmd(branch)
  return {
    'sh',
    '-c',
    ('tea pr list --state open --output json --fields index,head | jq -r \'[.[] | select(.head=="%s" or .head.name=="%s")][0].index // empty\''):format(
      branch,
      branch
    ),
  }
end

---@param num string
---@return string[]
function M:checks_json_cmd(num)
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
    ('SHA=$(tea api "/repos/:owner/:repo/pulls/%s" 2>/dev/null | jq -r ".head.sha // empty") && [ -n "$SHA" ] && tea api "/repos/:owner/:repo/commits/$SHA/status" 2>/dev/null | jq -r \'%s\''):format(
      num,
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
function M:check_log_cmd(run_id, failed_only, job_id)
  local _ = failed_only
  local lines = forge.config().ci.lines
  local job_flag = job_id and (' --job %s'):format(job_id) or ''
  return {
    'sh',
    '-c',
    ('tea actions runs logs %s%s | tail -n %d'):format(run_id, job_flag, lines),
  }
end

---@param run_id string
---@return string[]
function M:check_tail_cmd(run_id)
  return { 'tea', 'actions', 'runs', 'logs', run_id, '--follow' }
end

---@param run_id string
---@param job_id string?
---@return string[]
function M:live_tail_cmd(run_id, job_id)
  local cmd = { 'tea', 'actions', 'runs', 'logs', run_id, '--follow' }
  if job_id then
    table.insert(cmd, '--job')
    table.insert(cmd, job_id)
  end
  return cmd
end

function M:list_runs_json_cmd(branch)
  local limit = tostring(forge.config().display.limits.runs)
  local cmd = 'tea api "/repos/:owner/:repo/actions/runs?limit=' .. limit
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

function M:run_log_cmd(id, failed_only)
  local _ = failed_only
  local lines = forge.config().ci.lines
  return {
    'sh',
    '-c',
    ('tea actions runs logs %s | tail -n %d'):format(id, lines),
  }
end

function M:run_tail_cmd(id)
  return { 'tea', 'actions', 'runs', 'logs', id, '--follow' }
end

---@param num string
---@param method string
---@return string[]
function M:merge_cmd(num, method)
  return { 'tea', 'pr', 'merge', num, '--style', method }
end

---@param num string
---@return string[]
function M:approve_cmd(num)
  return { 'tea', 'pr', 'approve', num }
end

---@param num string
---@return string[]
function M:close_cmd(num)
  return { 'tea', 'pulls', 'close', num }
end

---@param num string
---@return string[]
function M:reopen_cmd(num)
  return { 'tea', 'pulls', 'reopen', num }
end

---@param num string
---@return string[]
function M:close_issue_cmd(num)
  return { 'tea', 'issues', 'close', num }
end

---@param num string
---@return string[]
function M:reopen_issue_cmd(num)
  return { 'tea', 'issues', 'reopen', num }
end

---@param title string
---@param body string
---@param base string
---@param _draft boolean
---@param _reviewers string[]?
---@return string[]
function M:create_pr_cmd(title, body, base, _draft, _reviewers)
  return { 'tea', 'pr', 'create', '--title', title, '--description', body, '--base', base }
end

---@return string[]?
function M:create_pr_web_cmd()
  local branch = vim.trim(vim.fn.system('git branch --show-current'))
  local base_url = forge.remote_web_url()
  local default = vim.trim(
    vim.fn.system(
      "git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'"
    )
  )
  if default == '' then
    default = 'main'
  end
  vim.ui.open(('%s/compare/%s...%s'):format(base_url, default, branch))
  return nil
end

---@param title string
---@param body string
---@param _labels string[]?
---@param _assignees string[]?
---@return string[]
function M:create_issue_cmd(title, body, _labels, _assignees)
  return { 'tea', 'issues', 'create', '--title', title, '--description', body }
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
function M:default_branch_cmd()
  return {
    'sh',
    '-c',
    "git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'"
      .. " || tea api /repos/:owner/:repo 2>/dev/null | jq -r '.default_branch // empty'",
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
function M:repo_info()
  local result = vim.system({ 'tea', 'api', '/repos/:owner/:repo' }, { text = true }):wait()
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
function M:pr_state(num)
  local result = vim
    .system({ 'tea', 'pr', num, '--fields', 'state,mergeable', '--output', 'json' }, { text = true })
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

function M:list_releases_json_cmd()
  local limit = tostring(forge.config().display.limits.releases)
  return {
    'sh',
    '-c',
    'tea api "/repos/:owner/:repo/releases?limit=' .. limit .. '"',
  }
end

function M:release_json_fields()
  return {
    tag = 'tag_name',
    title = 'name',
    is_draft = 'draft',
    is_prerelease = 'prerelease',
    published_at = 'published_at',
  }
end

---@param tag string
function M:browse_release(tag)
  local base = forge.remote_web_url()
  vim.ui.open(base .. '/releases/tag/' .. tag)
end

---@param tag string
---@return string[]
function M:delete_release_cmd(tag)
  return {
    'sh',
    '-c',
    "tea api -X DELETE '/repos/:owner/:repo/releases/tags/" .. tag .. "'",
  }
end

return M
