local config_mod = require('forge.config')
local log = require('forge.logger')
local repo_mod = require('forge.repo')
local scope_mod = require('forge.scope')
local submission = require('forge.compose.submission')

---@param value any
---@return string?
local function nonempty(value)
  if type(value) ~= 'string' then
    return nil
  end
  local trimmed = vim.trim(value)
  return trimmed ~= '' and trimmed or nil
end

---@class forge.Forgejo: forge.Forge
local M = {
  name = 'forgejo',
  cli = 'tea',
  kinds = { issue = 'issues', pr = 'pulls' },
  labels = {
    forge_name = 'Forgejo',
    issue = 'Issues',
    pr = 'PRs',
    pr_one = 'PR',
    pr_full = 'Pull Requests',
    ci = 'CI/CD',
    ci_inline = 'CI/CD runs',
  },
  capabilities = {
    draft = false,
    per_pr_checks = true,
    ci_json = true,
  },
  submission = {
    issue = {
      create = { labels = true, assignees = true, milestone = true },
      update = { labels = true, assignees = false, milestone = true },
    },
    pr = {
      create = {
        draft = false,
        reviewers = false,
        labels = true,
        assignees = true,
        milestone = true,
      },
      update = {
        draft = false,
        reviewers = true,
        labels = true,
        assignees = false,
        milestone = true,
      },
    },
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

local function repo_arg(scope)
  local current = scope or repo_mod.current_scope(M.name)
  return repo_mod.scope_repo_arg(current) or ''
end

local function append_csv(cmd, flag, values)
  if values and #values > 0 then
    table.insert(cmd, flag)
    table.insert(cmd, table.concat(values, ','))
  end
end

---@param state string
---@param limit integer?
---@param scope forge.Scope?
---@return string[]
function M:list_pr_json_cmd(state, limit, scope)
  return {
    'tea',
    'pulls',
    'list',
    '--state',
    state,
    '--limit',
    tostring(limit or config_mod.config().display.limits.pulls),
    '--output',
    'json',
    '--fields',
    'index,title,head,state,poster,created_at',
    '--repo',
    repo_arg(scope),
  }
end

---@param state string
---@param limit integer?
---@param scope forge.Scope?
---@return string[]
function M:list_issue_json_cmd(state, limit, scope)
  return {
    'tea',
    'issues',
    'list',
    '--state',
    state,
    '--limit',
    tostring(limit or config_mod.config().display.limits.issues),
    '--output',
    'json',
    '--fields',
    'index,title,state,poster,created_at',
    '--repo',
    repo_arg(scope),
  }
end

---@param kind string
---@param num string
---@param scope forge.Scope?
function M:view_web(kind, num, scope)
  local base = repo_mod.remote_web_url(scope)
  vim.ui.open(('%s/%s/%s'):format(base, kind, num))
end

---@param num string
---@param scope forge.Scope?
function M:browse_subject(num, scope)
  local cmd = {
    'tea',
    'api',
    '--repo',
    repo_arg(scope),
    ('/repos/{owner}/{repo}/issues/%s'):format(num),
  }
  local parse_err = ('failed to parse #%s details'):format(num)
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local stderr = vim.trim(result.stderr or '')
        if stderr:match('404') or stderr:match('not[%s_-]?found') then
          log.warn(('no %s or issue found for #%s'):format(M.labels.pr_one, num))
        else
          log.error(
            stderr ~= '' and stderr or ('no %s or issue found for #%s'):format(M.labels.pr_one, num)
          )
        end
        return
      end
      local ok, data = pcall(vim.json.decode, result.stdout or '{}')
      if not ok or type(data) ~= 'table' then
        log.error(parse_err)
        return
      end
      local url = type(data.html_url) == 'string' and data.html_url or ''
      if url == '' then
        log.error(parse_err)
        return
      end
      local _, open_err = vim.ui.open(url)
      if open_err then
        log.error(open_err)
      end
    end)
  end)
end

---@param loc string
---@param branch string
---@param scope forge.Scope?
function M:browse(loc, branch, scope)
  local base = repo_mod.remote_web_url(scope)
  local file, lines = loc:match('^(.+):(.+)$')
  vim.ui.open(('%s/src/branch/%s/%s#L%s'):format(base, branch, file, lines))
end

---@param branch string
---@param scope forge.Scope?
function M:browse_branch(branch, scope)
  local base = repo_mod.remote_web_url(scope)
  vim.ui.open(base .. '/src/branch/' .. branch)
end

---@param commit string
---@param scope forge.Scope?
function M:browse_commit(commit, scope)
  local base = repo_mod.remote_web_url(scope)
  vim.ui.open(base .. '/commit/' .. commit)
end

local LIST_PATHS = {
  pr = '/pulls',
  issue = '/issues',
  ci = '/actions',
  release = '/releases',
}

---@param kind forge.WebKind
---@param scope forge.Scope?
---@return string?
function M:list_web_url(kind, scope)
  local base = repo_mod.remote_web_url(scope)
  if not base or base == '' then
    return nil
  end
  local path = LIST_PATHS[kind]
  if not path then
    return nil
  end
  return base .. path
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:checkout_cmd(num, scope)
  return { 'tea', 'pr', 'checkout', num, '--repo', repo_arg(scope) }
end

---@param num string
---@return string[]
function M:fetch_pr(num)
  return { 'git', 'fetch', 'origin', ('pull/%s/head:pr-%s'):format(num, num) }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:pr_base_cmd(num, scope)
  return { 'tea', 'pr', num, '--fields', 'base', '--output', 'simple', '--repo', repo_arg(scope) }
end

---@param branch string
---@param scope forge.Scope?
---@param state forge.PRListState?
---@return string[]
function M:pr_for_branch_cmd(branch, scope, state)
  return {
    'sh',
    '-c',
    ('tea pr list --state %s --output json --fields index,head --repo %s | jq -r \'.[] | select(.head=="%s" or .head.name=="%s") | .index // empty\''):format(
      state or 'open',
      repo_arg(scope),
      branch,
      branch
    ),
  }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:checks_json_cmd(num, scope)
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
      repo_arg(scope),
      num,
      repo_arg(scope),
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
---@param scope forge.Scope?
---@return string[]
function M:check_log_cmd(run_id, failed_only, job_id, scope)
  local _ = failed_only
  local lines = config_mod.config().ci.lines
  local job_flag = job_id and (' --job %s'):format(job_id) or ''
  return {
    'sh',
    '-c',
    ('tea actions runs logs %s --repo %s%s | tail -n %d'):format(
      run_id,
      repo_arg(scope),
      job_flag,
      lines
    ),
  }
end

---@param run_id string
---@param job_id string?
---@param scope forge.Scope?
---@return string[]
function M:live_tail_cmd(run_id, job_id, scope)
  local cmd = { 'tea', 'actions', 'runs', 'logs', run_id, '--follow', '--repo', repo_arg(scope) }
  if job_id then
    table.insert(cmd, '--job')
    table.insert(cmd, job_id)
  end
  return cmd
end

---@param branch string?
---@param scope forge.Scope?
---@param limit integer?
---@return string[]
function M:list_runs_json_cmd(branch, scope, limit)
  local limit_arg = tostring(limit or config_mod.config().display.limits.runs)
  local cmd = 'tea api --repo '
    .. repo_arg(scope)
    .. ' "/repos/{owner}/{repo}/actions/runs?limit='
    .. limit_arg
  if branch then
    cmd = cmd .. '&branch=' .. branch
  end
  cmd = cmd .. '" 2>/dev/null | jq -r ".workflow_runs // []"'
  return { 'sh', '-c', cmd }
end

---@param id string
---@param scope forge.Scope?
---@return string[]
function M:cancel_run_cmd(id, scope)
  return {
    'tea',
    'api',
    '--repo',
    repo_arg(scope),
    '-X',
    'POST',
    ('/repos/{owner}/{repo}/actions/runs/%s/cancel'):format(id),
  }
end

---@param id string
---@param scope forge.Scope?
---@return string[]
function M:rerun_run_cmd(id, scope)
  return {
    'tea',
    'api',
    '--repo',
    repo_arg(scope),
    '-X',
    'POST',
    ('/repos/{owner}/{repo}/actions/runs/%s/rerun'):format(id),
  }
end

---@param id string
---@param scope forge.Scope?
---@return string?
function M:run_web_url(id, scope)
  local base = repo_mod.remote_web_url(scope)
  if not base or base == '' then
    return nil
  end
  return ('%s/actions/runs/%s'):format(base, id)
end

---@param id string
---@param scope forge.Scope?
function M:browse_run(id, scope)
  local url = self:run_web_url(id, scope)
  if not url then
    return
  end
  vim.ui.open(url)
end

---@param entry table
---@return forge.CIRun
function M:normalize_run(entry)
  local status = entry.status or ''
  if status == 'completed' then
    status = entry.conclusion or 'unknown'
  end
  local name = entry.display_title or entry.displayTitle or entry.name or ''
  local context = entry.workflow_name or entry.workflowName or entry.name or ''
  return {
    id = tostring(entry.id or ''),
    name = name,
    context = context,
    branch = entry.head_branch or entry.headBranch or '',
    status = status,
    event = entry.event or '',
    url = entry.html_url or '',
    created_at = entry.created_at or entry.createdAt or '',
  }
end

---@param id string
---@param failed_only boolean
---@param scope forge.Scope?
---@return string[]
function M:run_log_cmd(id, failed_only, scope)
  local _ = failed_only
  local lines = config_mod.config().ci.lines
  return {
    'sh',
    '-c',
    ('tea actions runs logs %s --repo %s | tail -n %d'):format(id, repo_arg(scope), lines),
  }
end

---@param num string
---@param method string
---@param scope forge.Scope?
---@return string[]
function M:merge_cmd(num, method, scope)
  local cmd = { 'tea', 'pr', 'merge', num }
  if method and method ~= '' then
    table.insert(cmd, '--style')
    table.insert(cmd, method)
  end
  table.insert(cmd, '--repo')
  table.insert(cmd, repo_arg(scope))
  return cmd
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:approve_cmd(num, scope)
  return { 'tea', 'pr', 'approve', num, '--repo', repo_arg(scope) }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:close_cmd(num, scope)
  return { 'tea', 'pulls', 'close', num, '--repo', repo_arg(scope) }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:reopen_cmd(num, scope)
  return { 'tea', 'pulls', 'reopen', num, '--repo', repo_arg(scope) }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:close_issue_cmd(num, scope)
  return { 'tea', 'issues', 'close', num, '--repo', repo_arg(scope) }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:reopen_issue_cmd(num, scope)
  return { 'tea', 'issues', 'reopen', num, '--repo', repo_arg(scope) }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:fetch_pr_details_cmd(num, scope)
  return {
    'sh',
    '-c',
    ('tea api --repo %s "/repos/{owner}/{repo}/pulls/%s"'):format(repo_arg(scope), num),
  }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:fetch_issue_details_cmd(num, scope)
  return {
    'sh',
    '-c',
    ('tea api --repo %s "/repos/{owner}/{repo}/issues/%s"'):format(repo_arg(scope), num),
  }
end

---@param num string
---@param title string
---@param body string
---@param scope forge.Scope?
---@param metadata forge.CommentMetadata?
---@param previous forge.CommentMetadata?
---@return string[]
function M:update_pr_cmd(num, title, body, scope, metadata, previous)
  local cmd = {
    'tea',
    'pr',
    'edit',
    num,
    '--title',
    title,
    '--description',
    body,
    '--repo',
    repo_arg(scope),
  }
  local current = submission.filter(self, 'pr', 'update', metadata)
  local before = previous or { labels = {}, reviewers = {}, milestone = '' }
  local add_labels, remove_labels = submission.diff(before.labels, current.labels)
  local add_reviewers, remove_reviewers = submission.diff(before.reviewers, current.reviewers)
  append_csv(cmd, '--add-labels', add_labels)
  append_csv(cmd, '--remove-labels', remove_labels)
  append_csv(cmd, '--add-reviewers', add_reviewers)
  append_csv(cmd, '--remove-reviewers', remove_reviewers)
  if current.milestone ~= (before.milestone or '') then
    table.insert(cmd, '--milestone')
    table.insert(cmd, current.milestone)
  end
  return cmd
end

---@param num string
---@param title string
---@param body string
---@param scope forge.Scope?
---@param metadata forge.CommentMetadata?
---@param previous forge.CommentMetadata?
---@return string[]
function M:update_issue_cmd(num, title, body, scope, metadata, previous)
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
    repo_arg(scope),
  }
  local current = submission.filter(self, 'issue', 'update', metadata)
  local before = previous or { labels = {}, milestone = '' }
  local add_labels, remove_labels = submission.diff(before.labels, current.labels)
  append_csv(cmd, '--add-labels', add_labels)
  append_csv(cmd, '--remove-labels', remove_labels)
  if current.milestone ~= (before.milestone or '') then
    table.insert(cmd, '--milestone')
    table.insert(cmd, current.milestone)
  end
  return cmd
end

---@param json table
---@param base_scope forge.Scope?
---@return forge.HeadRef
function M:parse_pr_head(json, base_scope)
  local head = type(json.head) == 'table' and json.head or nil
  local raw_branch = head and (head.ref or head.name) or json.head
  local branch = nonempty(raw_branch)
  local repo = head and type(head.repo) == 'table' and head.repo or nil
  local full_name = nonempty(repo and (repo.full_name or repo.fullName))
  local scope = nil
  if full_name then
    local host = type(base_scope) == 'table' and base_scope.host or 'codeberg.org'
    scope = scope_mod.from_url('forgejo', ('https://%s/%s'):format(host, full_name))
  end
  return {
    branch = branch,
    scope = scope,
  }
end

---@param expected forge.HeadRef
---@param actual forge.HeadRef
---@return boolean?, string?
function M:match_head(expected, actual)
  if nonempty(actual.branch) ~= expected.branch then
    return false
  end
  return scope_mod.same(expected.scope, actual.scope)
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
  local milestone = ''
  if type(json.milestone) == 'table' and json.milestone.title then
    milestone = json.milestone.title
  end
  return {
    title = json.title or '',
    body = json.body or '',
    draft = json.draft == true,
    head_branch = type(json.head) == 'table' and (json.head.ref or '') or json.head or '',
    base_branch = type(json.base) == 'table' and (json.base.ref or '') or json.base or '',
    labels = labels,
    assignees = assignees,
    reviewers = (function()
      local reviewers = {}
      for _, reviewer in ipairs(json.requested_reviewers or json.reviewers or {}) do
        table.insert(reviewers, reviewer.login or reviewer.username or '')
      end
      return reviewers
    end)(),
    milestone = milestone,
  }
end

---@param json table
---@return forge.IssueDetails
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
---@param _draft boolean
---@param scope forge.Scope?
---@param metadata forge.CommentMetadata?
---@return string[]
function M:create_pr_cmd(title, body, base, _draft, scope, metadata)
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
    repo_arg(scope),
  }
  local current = metadata and submission.filter(self, 'pr', 'create', metadata) or nil
  append_csv(cmd, '--labels', current and current.labels or {})
  append_csv(cmd, '--assignees', current and current.assignees or {})
  if current and current.milestone ~= '' then
    table.insert(cmd, '--milestone')
    table.insert(cmd, current.milestone)
  end
  return cmd
end

---@param scope forge.Scope?
---@param head_branch string?
---@param base_branch string?
---@return string
function M:create_pr_web_url(scope, _, head_branch, base_branch)
  local branch = head_branch or vim.trim(vim.fn.system('git branch --show-current'))
  local base_url = repo_mod.remote_web_url(scope)
  local default = base_branch
  if not default or default == '' then
    default = vim.trim(
      vim.fn.system(
        "git symbolic-scope refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'"
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
---@param scope forge.Scope?
---@param metadata forge.CommentMetadata?
---@return string[]
function M:create_issue_cmd(title, body, labels, scope, metadata)
  local cmd = {
    'tea',
    'issues',
    'create',
    '--title',
    title,
    '--description',
    body,
    '--repo',
    repo_arg(scope),
  }
  local current = metadata and submission.filter(self, 'issue', 'create', metadata) or nil
  local effective_labels = current and current.labels or labels or {}
  append_csv(cmd, '--labels', effective_labels)
  append_csv(cmd, '--assignees', current and current.assignees or {})
  if current and current.milestone ~= '' then
    table.insert(cmd, '--milestone')
    table.insert(cmd, current.milestone)
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

---@param scope forge.Scope?
---@return string[]
function M:default_branch_cmd(scope)
  return {
    'sh',
    '-c',
    "git symbolic-scope refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'"
      .. ' || tea api --repo '
      .. repo_arg(scope)
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

---@param scope forge.Scope?
---@return forge.RepoInfo
function M:repo_info(scope)
  local result = vim
    .system({ 'tea', 'api', '--repo', repo_arg(scope), '/repos/{owner}/{repo}' }, { text = true })
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
---@param scope forge.Scope?
---@return forge.PRState
function M:pr_state(num, scope)
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
      repo_arg(scope),
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

---@param scope forge.Scope?
---@param limit integer?
---@return string[]
function M:list_releases_json_cmd(scope, limit)
  local limit_arg = tostring(limit or config_mod.config().display.limits.releases)
  return {
    'sh',
    '-c',
    'tea releases list --limit ' .. limit_arg .. ' --output json --repo ' .. repo_arg(scope),
  }
end

---@param tag string
---@param scope forge.Scope?
function M:browse_release(tag, scope)
  local base = repo_mod.remote_web_url(scope)
  vim.ui.open(base .. '/releases/tag/' .. tag)
end

---@param tag string
---@param scope forge.Scope?
---@return string[]
function M:delete_release_cmd(tag, scope)
  return {
    'sh',
    '-c',
    'tea releases delete --confirm --repo ' .. repo_arg(scope) .. ' ' .. tag,
  }
end

return M
