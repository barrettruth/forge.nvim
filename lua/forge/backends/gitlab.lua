local config_mod = require('forge.config')
local log = require('forge.logger')
local repo_mod = require('forge.repo')
local scope_mod = require('forge.scope')
local submission = require('forge.submission')

---@param value any
---@return string?
local function nonempty(value)
  if type(value) ~= 'string' then
    return nil
  end
  local trimmed = vim.trim(value)
  return trimmed ~= '' and trimmed or nil
end

---@type table<string, string|false>
local project_id_cache = {}

---@class forge.GitLab: forge.Forge
local M = {
  name = 'gitlab',
  cli = 'glab',
  kinds = { issue = 'issue', pr = 'mr' },
  labels = {
    forge_name = 'GitLab',
    issue = 'Issues',
    pr = 'Merge Requests',
    pr_one = 'MR',
    pr_full = 'Merge Requests',
    ci = 'Pipelines',
    ci_inline = 'pipelines',
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

local function repo_arg(scope)
  return repo_mod.scope_repo_arg(scope) or repo_mod.remote_web_url()
end

local function project(scope)
  local current = scope or repo_mod.current_scope(M.name)
  return scope_mod.encode_project(current) or ''
end

local function hostname(scope)
  local current = scope or repo_mod.current_scope(M.name)
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
---@param scope forge.Scope?
---@return string[]
function M:list_pr_json_cmd(state, limit, scope)
  local cmd = {
    'glab',
    'mr',
    'list',
    '--per-page',
    tostring(limit or config_mod.config().display.limits.pulls),
    '--output',
    'json',
  }
  local repo = repo_arg(scope)
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
---@param scope forge.Scope?
---@return string[]
function M:list_issue_json_cmd(state, limit, scope)
  local cmd = {
    'glab',
    'issue',
    'list',
    '--per-page',
    tostring(limit or config_mod.config().display.limits.issues),
    '--output',
    'json',
  }
  local repo = repo_arg(scope)
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
---@param scope forge.Scope?
function M:view_web(kind, num, scope)
  vim.system({ 'glab', kind, 'view', num, '--web', '-R', repo_arg(scope) })
end

---@param num string
---@param scope forge.Scope?
function M:browse_subject(num, scope)
  local current = scope or repo_mod.current_scope(M.name)
  local pid = project(current)
  local host = hostname(current) or 'gitlab.com'
  if pid == '' then
    log.error('failed to resolve repo for browse')
    return
  end

  local pending = 2
  ---@type string?
  local mr_url = nil
  ---@type string?
  local issue_url = nil

  local function finalize()
    pending = pending - 1
    if pending > 0 then
      return
    end
    if mr_url and issue_url then
      log.warn(
        ('ambiguous: %s and issue #%s both exist; use :Forge pr browse %s or :Forge issue browse %s'):format(
          M.labels.pr_one,
          num,
          num,
          num
        )
      )
      return
    end
    local url = mr_url or issue_url
    if not url or url == '' then
      log.warn(('no %s or issue found for #%s'):format(M.labels.pr_one, num))
      return
    end
    local _, open_err = vim.ui.open(url)
    if open_err then
      log.error(open_err)
    end
  end

  ---@param path string
  ---@param set_url fun(url: string)
  local function probe(path, set_url)
    vim.system({ 'glab', 'api', '--hostname', host, path }, { text = true }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          local ok, data = pcall(vim.json.decode, result.stdout or '{}')
          if ok and type(data) == 'table' then
            local web_url = type(data.web_url) == 'string' and data.web_url or ''
            if web_url ~= '' then
              set_url(web_url)
            end
          end
        end
        finalize()
      end)
    end)
  end

  probe(('projects/%s/merge_requests/%s'):format(pid, num), function(u)
    mr_url = u
  end)
  probe(('projects/%s/issues/%s'):format(pid, num), function(u)
    issue_url = u
  end)
end

---@param loc string
---@param branch string
---@param scope forge.Scope?
function M:browse(loc, branch, scope)
  local base = repo_mod.remote_web_url(scope)
  local file, lines = loc:match('^(.+):(.+)$')
  vim.ui.open(('%s/-/blob/%s/%s#L%s'):format(base, branch, file, lines))
end

---@param branch string
---@param scope forge.Scope?
function M:browse_branch(branch, scope)
  local base = repo_mod.remote_web_url(scope)
  vim.ui.open(base .. '/-/tree/' .. branch)
end

---@param commit string
---@param scope forge.Scope?
function M:browse_commit(commit, scope)
  local base = repo_mod.remote_web_url(scope)
  vim.ui.open(base .. '/-/commit/' .. commit)
end

local LIST_PATHS = {
  pr = '/-/merge_requests',
  issue = '/-/issues',
  ci = '/-/pipelines',
  release = '/-/releases',
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
  return { 'glab', 'mr', 'checkout', num, '-R', repo_arg(scope) }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:fetch_pr(num, scope)
  local remote = 'origin'
  local current = repo_mod.current_scope(M.name)
  if
    scope
    and repo_mod.scope_key(scope) ~= ''
    and repo_mod.scope_key(scope) ~= repo_mod.scope_key(current)
  then
    remote = repo_mod.remote_web_url(scope) .. '.git'
  end
  return {
    'git',
    'fetch',
    remote,
    ('merge-requests/%s/head:mr-%s'):format(num, num),
  }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:pr_base_cmd(num, scope)
  return {
    'sh',
    '-c',
    ("glab mr view %s -F json -R '%s' | jq -r .target_branch"):format(num, repo_arg(scope)),
  }
end

---@param branch string
---@param scope forge.Scope?
---@param state forge.PRListState?
---@return string[]
function M:pr_for_branch_cmd(branch, scope, state)
  local flag = ''
  if state == 'closed' then
    flag = ' --closed'
  elseif state == 'merged' then
    flag = ' --merged'
  elseif state == 'all' then
    flag = ' --all'
  end
  return {
    'sh',
    '-c',
    ("glab mr list --source-branch '%s'%s -F json -R '%s' | jq -r '.[].iid // empty'"):format(
      branch,
      flag,
      repo_arg(scope)
    ),
  }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:checks_json_cmd(num, scope)
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
      hostname(scope) or 'gitlab.com',
      project(scope),
      num,
      hostname(scope) or 'gitlab.com',
      project(scope),
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
---@param scope forge.Scope?
---@return string[]
function M:check_log_cmd(run_id, failed_only, job_id, scope)
  local _ = failed_only
  local lines = config_mod.config().ci.lines
  local id = job_id or run_id
  return {
    'sh',
    '-c',
    ("glab ci trace %s -R '%s' | tail -n %d"):format(id, repo_arg(scope), lines),
  }
end

---@param run_id string
---@param scope forge.Scope?
---@return string[]
function M:live_tail_cmd(run_id, _, scope)
  return { 'glab', 'ci', 'trace', run_id, '-R', repo_arg(scope) }
end

---@param id string?
---@param scope forge.Scope?
---@return string[]
function M:watch_cmd(id, scope)
  local cmd = { 'glab', 'ci', 'view' }
  table.insert(cmd, '-R')
  table.insert(cmd, repo_arg(scope))
  if id then
    table.insert(cmd, '-p')
    table.insert(cmd, id)
  end
  return cmd
end

---@param id string
---@param scope forge.Scope?
---@return string[]
function M:cancel_run_cmd(id, scope)
  return { 'glab', 'ci', 'cancel', 'pipeline', id, '-R', repo_arg(scope) }
end

---@param id string
---@param scope forge.Scope?
---@return string[]
function M:rerun_run_cmd(id, scope)
  return {
    'glab',
    'api',
    '--hostname',
    hostname(scope) or 'gitlab.com',
    '--method',
    'POST',
    ('projects/%s/pipelines/%s/retry'):format(project(scope), id),
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
  return ('%s/-/pipelines/%s'):format(base, id)
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

---@param branch string?
---@param scope forge.Scope?
---@param limit integer?
---@return string[]
function M:list_runs_json_cmd(branch, scope, limit)
  local cmd = {
    'glab',
    'ci',
    'list',
    '--output',
    'json',
    '--per-page',
    tostring(limit or config_mod.config().display.limits.runs),
    '-R',
    repo_arg(scope),
  }
  if branch then
    table.insert(cmd, '--ref')
    table.insert(cmd, branch)
  end
  return cmd
end

---@param entry table
---@return forge.CIRun
function M:normalize_run(entry)
  local ref = entry.ref or ''
  local mr_num = ref:match('^refs/merge%-requests/(%d+)/head$')
  local context = mr_num and ('!%s'):format(mr_num) or ''
  return {
    id = tostring(entry.id or ''),
    name = entry.name or (context ~= '' and context or ref),
    context = context,
    branch = context ~= '' and '' or ref,
    status = entry.status or '',
    event = entry.source or '',
    url = entry.web_url or '',
    created_at = entry.created_at or '',
  }
end

---@param id string
---@param failed_only boolean
---@param scope forge.Scope?
---@return string[]
function M:run_log_cmd(id, failed_only, scope)
  local lines = config_mod.config().ci.lines
  local jq_filter = failed_only and '[.[] | select(.status=="failed")][0].id // .[0].id'
    or '.[0].id'
  return {
    'sh',
    '-c',
    ('JOB=$(glab api --hostname %s \'projects/%s/pipelines/%s/jobs?per_page=100\' | jq -r \'%s\') && [ "$JOB" != "null" ] && glab ci trace "$JOB" -R \'%s\' | tail -n %d'):format(
      hostname(scope) or 'gitlab.com',
      project(scope),
      id,
      jq_filter,
      repo_arg(scope),
      lines
    ),
  }
end

---@param num string
---@param method string
---@param scope forge.Scope?
---@return string[]
function M:merge_cmd(num, method, scope)
  local cmd = { 'glab', 'mr', 'merge', num }
  table.insert(cmd, '-R')
  table.insert(cmd, repo_arg(scope))
  if method == 'squash' then
    table.insert(cmd, '--squash')
  elseif method == 'rebase' then
    table.insert(cmd, '--rebase')
  end
  return cmd
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:approve_cmd(num, scope)
  return { 'glab', 'mr', 'approve', num, '-R', repo_arg(scope) }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:close_cmd(num, scope)
  return { 'glab', 'mr', 'close', num, '-R', repo_arg(scope) }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:reopen_cmd(num, scope)
  return { 'glab', 'mr', 'reopen', num, '-R', repo_arg(scope) }
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
---@param scope forge.Scope?
---@return string[]
function M:fetch_pr_details_cmd(num, scope)
  return { 'glab', 'mr', 'view', num, '--output', 'json', '-R', repo_arg(scope) }
end

---@param num string
---@param scope forge.Scope?
---@return string[]
function M:fetch_issue_details_cmd(num, scope)
  return { 'glab', 'issue', 'view', num, '--output', 'json', '-R', repo_arg(scope) }
end

---@param num string
---@param title string
---@param body string
---@param scope forge.Scope?
---@param metadata forge.CommentMetadata?
---@param previous forge.CommentMetadata?
---@return string[]
function M:update_pr_cmd(num, title, body, scope, metadata, previous)
  local cmd =
    { 'glab', 'mr', 'update', num, '--title', title, '--description', body, '-R', repo_arg(scope) }
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

---@param num string
---@param title string
---@param body string
---@param scope forge.Scope?
---@param metadata forge.CommentMetadata?
---@param previous forge.CommentMetadata?
---@return string[]
function M:update_issue_cmd(num, title, body, scope, metadata, previous)
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
    repo_arg(scope),
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
---@param _base_scope forge.Scope?
---@return forge.HeadRef
function M:parse_pr_head(json, _base_scope)
  return {
    branch = nonempty(json.source_branch),
    project_id = json.source_project_id ~= nil and tostring(json.source_project_id) or nil,
  }
end

---Resolve the GitLab numeric project ID for a scope, caching the lookup.
---@param scope forge.Scope?
---@return string?, string?
local function resolve_project_id(scope)
  local slug = type(scope) == 'table' and scope.slug or 'scope'
  local host = type(scope) == 'table' and scope.host or 'gitlab.com'
  local key = scope_mod.key(scope)
  if key == '' then
    return nil
  end
  if project_id_cache[key] ~= nil then
    return project_id_cache[key] or nil
  end
  local encoded = scope_mod.encode_project(scope)
  if not encoded then
    project_id_cache[key] = false
    return nil
  end
  local result = vim
    .system({ 'glab', 'api', '--hostname', host, ('projects/%s'):format(encoded) }, { text = true })
    :wait()
  if result.code ~= 0 then
    local err = vim.trim(result.stderr or '')
    if err == '' then
      err = vim.trim(result.stdout or '')
    end
    if err == '' then
      err = ('failed to resolve GitLab project for %s'):format(slug)
    end
    return nil, err
  end
  local ok, json = pcall(vim.json.decode, result.stdout or '{}')
  if not ok or type(json) ~= 'table' or json.id == nil then
    return nil, ('failed to parse GitLab project for %s'):format(slug)
  end
  local id = tostring(json.id)
  project_id_cache[key] = id
  return id
end

---@param expected forge.HeadRef
---@param actual forge.HeadRef
---@return boolean?, string?
function M:match_head(expected, actual)
  if nonempty(actual.branch) ~= expected.branch then
    return false
  end
  local expected_id = expected.project_id
  if not expected_id and expected.scope then
    local id, err = resolve_project_id(expected.scope)
    if err then
      return nil, err
    end
    expected_id = id
  end
  local actual_id = nonempty(actual.project_id)
  return expected_id ~= nil and actual_id ~= nil and expected_id == actual_id
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

---@param json table
---@return forge.IssueDetails
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
---@param scope forge.Scope?
---@param metadata forge.CommentMetadata?
---@return string[]
function M:create_pr_cmd(title, body, base, draft, scope, metadata)
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
    repo_arg(scope),
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

---@param scope forge.Scope?
---@param head_scope forge.Scope?
---@param head_branch string?
---@param base_branch string?
---@return string[]
function M:create_pr_web_cmd(scope, head_scope, head_branch, base_branch)
  local cmd = { 'glab', 'mr', 'create', '--web', '-R', repo_arg(scope) }
  if
    head_scope
    and repo_mod.scope_key(head_scope) ~= ''
    and repo_mod.scope_key(head_scope) ~= repo_mod.scope_key(scope)
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
---@param scope forge.Scope?
---@param metadata forge.CommentMetadata?
---@return string[]
function M:create_issue_cmd(title, body, labels, scope, metadata)
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
    repo_arg(scope),
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

---@param scope forge.Scope?
---@return string[]
function M:create_issue_web_cmd(scope)
  return { 'glab', 'issue', 'create', '--web', '-R', repo_arg(scope) }
end

---@return string[]
function M:issue_template_paths()
  return { '.gitlab/issue_templates/' }
end

---@param scope forge.Scope?
---@return string[]
function M:default_branch_cmd(scope)
  return {
    'sh',
    '-c',
    "glab repo view -F json -R '" .. repo_arg(scope) .. "' | jq -r '.default_branch'",
  }
end

---@return string[]
function M:template_paths()
  return { '.gitlab/merge_request_templates/' }
end

---@param num string
---@param is_draft boolean
---@param scope forge.Scope?
---@return string[]?
function M:draft_toggle_cmd(num, is_draft, scope)
  if is_draft then
    return { 'glab', 'mr', 'update', num, '--ready', '-R', repo_arg(scope) }
  end
  return { 'glab', 'mr', 'update', num, '--draft', '-R', repo_arg(scope) }
end

---@param scope forge.Scope?
---@return forge.RepoInfo
function M:repo_info(scope)
  local result = vim
    .system({
      'glab',
      'api',
      '--hostname',
      hostname(scope) or 'gitlab.com',
      'projects/' .. project(scope),
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
---@param scope forge.Scope?
---@return forge.PRState
function M:pr_state(num, scope)
  local result = vim
    .system({ 'glab', 'mr', 'view', num, '--output', 'json', '-R', repo_arg(scope) }, { text = true })
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

---@param scope forge.Scope?
---@param limit integer?
---@return string[]
function M:list_releases_json_cmd(scope, limit)
  return {
    'glab',
    'release',
    'list',
    '--output',
    'json',
    '--per-page',
    tostring(limit or config_mod.config().display.limits.releases),
    '-R',
    repo_arg(scope),
  }
end

---@param tag string
---@param scope forge.Scope?
function M:browse_release(tag, scope)
  local base = repo_mod.remote_web_url(scope)
  vim.ui.open(base .. '/-/releases/' .. tag)
end

---@param tag string
---@param scope forge.Scope?
---@return string[]
function M:delete_release_cmd(tag, scope)
  return { 'glab', 'release', 'delete', tag, '-R', repo_arg(scope) }
end

return M
