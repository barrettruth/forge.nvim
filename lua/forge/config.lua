local M = {}

---@alias forge.Split 'horizontal'|'vertical'

---@class forge.Config
---@field picker 'fzf-lua'|'auto'
---@field debug boolean|string?
---@field split forge.Split
---@field ci forge.CIConfig
---@field sources table<string, forge.SourceConfig>
---@field keys forge.KeysConfig|false
---@field display forge.DisplayConfig

---@class forge.CIConfig
---@field lines integer
---@field split forge.Split?
---@field refresh integer

---@class forge.SourceConfig
---@field hosts string[]

---@class forge.KeysConfig
---@field pr forge.PRPickerKeys?
---@field issue forge.IssuePickerKeys?
---@field ci forge.CIPickerKeys?
---@field release forge.ReleasePickerKeys?
---@field log forge.LogViewerKeys?

---@class forge.PRPickerKeys
---@field checkout? string|false
---@field diff string|false
---@field worktree string|false
---@field ci string|false
---@field browse string|false
---@field manage? string|false
---@field edit? string|false
---@field create string|false
---@field close? string|false
---@field filter string|false
---@field refresh string|false

---@class forge.IssuePickerKeys
---@field browse string|false
---@field close string|false
---@field create string|false
---@field filter string|false
---@field refresh string|false

---@class forge.CIPickerKeys
---@field log string|false
---@field watch string|false
---@field browse string|false
---@field filter string|false
---@field failed? string|false
---@field passed? string|false
---@field running? string|false
---@field all? string|false
---@field refresh string|false

---@class forge.ReleasePickerKeys
---@field browse string|false
---@field yank string|false
---@field delete string|false
---@field filter string|false
---@field refresh string|false

---@class forge.LogViewerKeys
---@field close string|false
---@field next_step string|false
---@field prev_step string|false
---@field next_error string|false
---@field prev_error string|false
---@field browse string|false
---@field refresh string|false

---@class forge.DisplayConfig
---@field icons forge.IconsConfig
---@field widths forge.WidthsConfig
---@field limits forge.LimitsConfig

---@class forge.IconsConfig
---@field open string
---@field merged string
---@field closed string
---@field pass string
---@field fail string
---@field pending string
---@field skip string
---@field unknown string

---@class forge.WidthsConfig
---@field title integer
---@field author integer
---@field name integer
---@field branch integer

---@class forge.LimitsConfig
---@field pulls integer
---@field issues integer
---@field runs integer
---@field releases integer

---@class forge.PRState
---@field state string
---@field mergeable string
---@field review_decision string
---@field is_draft boolean

---@class forge.Check
---@field name string
---@field status string
---@field elapsed string
---@field run_id string

---@class forge.CIRun
---@field id string
---@field name string
---@field branch string
---@field status string
---@field event string
---@field url string
---@field created_at string

---@class forge.RepoInfo
---@field permission string
---@field merge_methods string[]

---@class forge.Capabilities
---@field draft boolean
---@field reviewers boolean
---@field per_pr_checks boolean
---@field ci_json boolean

---@class forge.Forge
---@field name string
---@field cli string
---@field kinds { issue: string, pr: string }
---@field labels { issue: string, pr: string, pr_one: string, pr_full: string, ci: string }
---@field capabilities forge.Capabilities
---@field list_pr_json_cmd fun(self: forge.Forge, state: string, limit?: integer): string[]
---@field list_issue_json_cmd fun(self: forge.Forge, state: string, limit?: integer): string[]
---@field pr_fields { number: string, title: string, branch: string, state: string, author: string, created_at: string }
---@field issue_fields { number: string, title: string, state: string, author: string, created_at: string }
---@field view_web fun(self: forge.Forge, kind: string, num: string)
---@field browse fun(self: forge.Forge, loc: string, branch: string)
---@field browse_branch fun(self: forge.Forge, branch: string)
---@field browse_commit fun(self: forge.Forge, sha: string)
---@field checkout_cmd fun(self: forge.Forge, num: string): string[]
---@field fetch_pr fun(self: forge.Forge, num: string): string[]
---@field pr_base_cmd fun(self: forge.Forge, num: string): string[]
---@field pr_for_branch_cmd fun(self: forge.Forge, branch: string): string[]
---@field checks_cmd fun(self: forge.Forge, num: string): string
---@field check_log_cmd fun(self: forge.Forge, run_id: string, failed_only: boolean, job_id: string?): string[]
---@field steps_cmd (fun(self: forge.Forge, run_id: string): string[])?
---@field view_cmd (fun(self: forge.Forge, id: string, opts?: { job_id?: string, log?: boolean, failed?: boolean }): string[])?
---@field summary_json_cmd (fun(self: forge.Forge, id: string): string[])?
---@field watch_cmd (fun(self: forge.Forge, id: string): string[])?
---@field run_status_cmd (fun(self: forge.Forge, id: string): string[])?
---@field live_tail_cmd (fun(self: forge.Forge, run_id: string, job_id: string?): string[])?
---@field list_runs_json_cmd fun(self: forge.Forge, branch: string?): string[]
---@field list_runs_cmd fun(self: forge.Forge, branch: string?): string
---@field normalize_run fun(self: forge.Forge, entry: table): forge.CIRun
---@field run_log_cmd fun(self: forge.Forge, id: string, failed_only: boolean): string[]
---@field merge_cmd fun(self: forge.Forge, num: string, method: string): string[]
---@field approve_cmd fun(self: forge.Forge, num: string): string[]
---@field repo_info fun(self: forge.Forge): forge.RepoInfo
---@field pr_state fun(self: forge.Forge, num: string): forge.PRState
---@field close_cmd fun(self: forge.Forge, num: string): string[]
---@field reopen_cmd fun(self: forge.Forge, num: string): string[]
---@field close_issue_cmd fun(self: forge.Forge, num: string): string[]
---@field reopen_issue_cmd fun(self: forge.Forge, num: string): string[]
---@field draft_toggle_cmd fun(self: forge.Forge, num: string, is_draft: boolean): string[]?
---@field create_pr_cmd fun(self: forge.Forge, title: string, body: string, base: string, draft: boolean, reviewers: string[]?, labels: string[]?, assignees: string[]?, milestone: string?): string[]
---@field update_pr_cmd fun(self: forge.Forge, num: string, title: string, body: string, reviewers: string[]?, labels: string[]?, assignees: string[]?, milestone: string?): string[]
---@field fetch_pr_details_cmd fun(self: forge.Forge, num: string): string[]
---@field parse_pr_details fun(self: forge.Forge, json: table): { title: string, body: string, draft: boolean, reviewers: string[], labels: string[], assignees: string[], milestone: string }
---@field completion_cmd (fun(self: forge.Forge, field: string): string[]?)?
---@field create_pr_web_cmd fun(self: forge.Forge): string[]?
---@field default_branch_cmd fun(self: forge.Forge): string[]
---@field checks_json_cmd (fun(self: forge.Forge, num: string): string[])?
---@field template_paths fun(self: forge.Forge): string[]
---@field list_releases_json_cmd fun(self: forge.Forge): string[]
---@field release_fields { tag: string, title: string, is_draft: string?, is_prerelease: string?, is_latest: string?, published_at: string }
---@field browse_release fun(self: forge.Forge, tag: string)
---@field delete_release_cmd fun(self: forge.Forge, tag: string): string[]
---@field create_issue_cmd fun(self: forge.Forge, title: string, body: string, labels: string[]?, assignees: string[]?, milestone: string?): string[]
---@field issue_template_paths fun(self: forge.Forge): string[]
---@field create_issue_web_cmd (fun(self: forge.Forge): string[]?)?

---@type forge.Config
local DEFAULTS = {
  picker = 'auto',
  client = 'picker',
  context = 'current',
  debug = false,
  split = 'horizontal',
  ci = { lines = 1000, refresh = 5 },
  sources = {},
  contexts = {
    current = true,
  },
  sections = {
    prs = true,
    issues = true,
    ci = true,
    browse = true,
    releases = true,
    branches = true,
    commits = true,
    worktrees = true,
  },
  routes = {
    prs = 'prs.open',
    issues = 'issues.open',
    ci = 'ci.current_branch',
    browse = 'browse.contextual',
    releases = 'releases.all',
    branches = 'branches.local',
    commits = 'commits.current_branch',
    worktrees = 'worktrees.list',
  },
  keys = {
    pr = {
      review = '<c-d>',
      diff = '<c-d>',
      worktree = '<c-w>',
      ci = '<c-t>',
      browse = '<c-x>',
      create = '<c-a>',
      filter = '<c-f>',
      refresh = '<c-r>',
    },
    issue = {
      browse = '<c-x>',
      close = '<c-s>',
      filter = '<c-f>',
      refresh = '<c-r>',
      create = '<c-a>',
    },
    ci = {
      log = '<cr>',
      watch = '<c-w>',
      browse = '<c-x>',
      filter = '<c-f>',
      refresh = '<c-r>',
    },
    release = {
      browse = '<cr>',
      yank = '<c-y>',
      delete = '<c-d>',
      filter = '<c-f>',
      refresh = '<c-r>',
    },
    branch = {
      review = '<c-d>',
      delete = '<c-s>',
      browse = '<c-x>',
      yank = '<c-y>',
      refresh = '<c-r>',
    },
    commit = {
      review = '<c-d>',
      browse = '<c-x>',
      yank = '<c-y>',
      refresh = '<c-r>',
    },
    worktree = {
      add = '<c-a>',
      delete = '<c-s>',
      yank = '<c-y>',
      refresh = '<c-r>',
    },
    log = {
      close = 'q',
      next_step = ']]',
      prev_step = '[[',
      next_error = ']e',
      prev_error = '[e',
      browse = 'gx',
      refresh = '<c-r>',
    },
  },
  display = {
    icons = {
      open = '+',
      merged = 'm',
      closed = 'x',
      pass = '*',
      fail = 'x',
      pending = '~',
      skip = '-',
      unknown = '?',
    },
    widths = {
      title = 45,
      author = 15,
      name = 35,
      branch = 25,
    },
    limits = {
      pulls = 100,
      issues = 100,
      runs = 30,
      releases = 30,
    },
  },
}

local hl_defaults = {
  -- TODO: https://github.com/barrettruth/forge.nvim/issues/33
  -- ForgeComposeComment = 'Comment',
  ForgeComposeComment = 'Comment',
  ForgeComposeBranch = 'Special',
  ForgeComposeForge = 'Label',
  ForgeComposeDraft = 'DiagnosticWarn',
  ForgeComposeFile = 'Constant',
  ForgeComposeAdded = 'Added',
  ForgeComposeRemoved = 'Removed',
  ForgeComposeHeader = 'PreProc',
  ForgeComposeLabel = 'Label',
  ForgeNumber = 'Number',
  ForgeOpen = 'DiagnosticInfo',
  ForgeMerged = 'Constant',
  ForgeClosed = 'Comment',
  ForgePass = 'DiagnosticOk',
  ForgeFail = 'DiagnosticError',
  ForgePending = 'DiagnosticWarn',
  ForgeSkip = 'Comment',
  ForgeBranch = 'Special',
  ForgeBranchCurrent = { bold = true },
  ForgeCommitHash = 'Number',
  ForgeCommitTime = 'Comment',
  ForgeCommitAuthor = 'Comment',
  ForgeDim = 'Comment',
  ForgeLogJob = 'Title',
  ForgeLogStep = 'Function',
  ForgeLogError = 'DiagnosticError',
  ForgeLogErrorLabel = { bold = true },
  ForgeLogWarning = 'DiagnosticWarn',
  ForgeLogWarningLabel = { bold = true },
  ForgeLogSection = 'Function',
  ForgeLogCommand = 'Special',
  ForgeLogDim = 'Comment',
}

function M.setup_highlights()
  for group, val in pairs(hl_defaults) do
    if type(val) == 'string' then
      vim.api.nvim_set_hl(0, group, { default = true, link = val })
    else
      vim.api.nvim_set_hl(0, group, vim.tbl_extend('keep', { default = true }, val))
    end
  end
end

---@return forge.Config
function M.config()
  local user = vim.g.forge or {}
  local cfg = vim.tbl_deep_extend('force', DEFAULTS, user)
  if user.keys == false then
    cfg.keys = false
  end

  local picker_backends = require('forge.picker').backends
  vim.validate('forge.picker', cfg.picker, function(v)
    return v == 'auto' or picker_backends[v] ~= nil
  end, "'auto' or 'fzf-lua'")
  vim.validate('forge.client', cfg.client, 'string')
  vim.validate('forge.context', cfg.context, 'string')
  vim.validate('forge.debug', cfg.debug, function(v)
    return v == false or v == true or type(v) == 'string'
  end, 'boolean or string')
  vim.validate('forge.sources', cfg.sources, 'table')
  vim.validate('forge.contexts', cfg.contexts, 'table')
  vim.validate('forge.sections', cfg.sections, 'table')
  vim.validate('forge.routes', cfg.routes, 'table')
  vim.validate('forge.keys', cfg.keys, function(v)
    return v == false or type(v) == 'table'
  end, 'table or false')
  vim.validate('forge.split', cfg.split, function(v)
    return v == 'horizontal' or v == 'vertical'
  end, "'horizontal' or 'vertical'")
  vim.validate('forge.display', cfg.display, 'table')
  vim.validate('forge.ci', cfg.ci, 'table')
  vim.validate('forge.ci.lines', cfg.ci.lines, 'number')
  vim.validate('forge.ci.refresh', cfg.ci.refresh, 'number')
  if cfg.ci.split ~= nil then
    vim.validate('forge.ci.split', cfg.ci.split, function(v)
      return v == 'horizontal' or v == 'vertical'
    end, "'horizontal' or 'vertical'")
  end

  vim.validate('forge.display.icons', cfg.display.icons, 'table')
  vim.validate('forge.display.icons.open', cfg.display.icons.open, 'string')
  vim.validate('forge.display.icons.merged', cfg.display.icons.merged, 'string')
  vim.validate('forge.display.icons.closed', cfg.display.icons.closed, 'string')
  vim.validate('forge.display.icons.pass', cfg.display.icons.pass, 'string')
  vim.validate('forge.display.icons.fail', cfg.display.icons.fail, 'string')
  vim.validate('forge.display.icons.pending', cfg.display.icons.pending, 'string')
  vim.validate('forge.display.icons.skip', cfg.display.icons.skip, 'string')
  vim.validate('forge.display.icons.unknown', cfg.display.icons.unknown, 'string')

  vim.validate('forge.display.widths', cfg.display.widths, 'table')
  vim.validate('forge.display.widths.title', cfg.display.widths.title, 'number')
  vim.validate('forge.display.widths.author', cfg.display.widths.author, 'number')
  vim.validate('forge.display.widths.name', cfg.display.widths.name, 'number')
  vim.validate('forge.display.widths.branch', cfg.display.widths.branch, 'number')

  vim.validate('forge.display.limits', cfg.display.limits, 'table')
  vim.validate('forge.display.limits.pulls', cfg.display.limits.pulls, 'number')
  vim.validate('forge.display.limits.issues', cfg.display.limits.issues, 'number')
  vim.validate('forge.display.limits.runs', cfg.display.limits.runs, 'number')
  vim.validate('forge.display.limits.releases', cfg.display.limits.releases, 'number')

  local key_or_false = function(v)
    return v == nil or v == false or type(v) == 'string'
  end
  if type(cfg.keys) == 'table' then
    local keys = cfg.keys --[[@as forge.KeysConfig]]
    if keys.pr ~= nil then
      vim.validate('forge.keys.pr', keys.pr, 'table')
      for _, k in ipairs({
        'checkout',
        'review',
        'diff',
        'worktree',
        'ci',
        'browse',
        'manage',
        'edit',
        'create',
        'close',
        'filter',
        'refresh',
      }) do
        vim.validate('forge.keys.pr.' .. k, keys.pr[k], key_or_false, 'string or false')
      end
    end
    if keys.issue ~= nil then
      vim.validate('forge.keys.issue', keys.issue, 'table')
      for _, k in ipairs({ 'browse', 'close', 'create', 'filter', 'refresh' }) do
        vim.validate('forge.keys.issue.' .. k, keys.issue[k], key_or_false, 'string or false')
      end
    end
    if keys.ci ~= nil then
      vim.validate('forge.keys.ci', keys.ci, 'table')
      for _, k in ipairs({
        'log',
        'watch',
        'browse',
        'filter',
        'failed',
        'passed',
        'running',
        'all',
        'refresh',
      }) do
        vim.validate('forge.keys.ci.' .. k, keys.ci[k], key_or_false, 'string or false')
      end
    end
    if keys.release ~= nil then
      vim.validate('forge.keys.release', keys.release, 'table')
      for _, k in ipairs({ 'browse', 'yank', 'delete', 'filter', 'refresh' }) do
        vim.validate('forge.keys.release.' .. k, keys.release[k], key_or_false, 'string or false')
      end
    end
    local branch_keys = rawget(keys, 'branch')
    if branch_keys ~= nil then
      vim.validate('forge.keys.branch', branch_keys, 'table')
      for _, k in ipairs({ 'review', 'delete', 'browse', 'yank', 'refresh' }) do
        vim.validate('forge.keys.branch.' .. k, branch_keys[k], key_or_false, 'string or false')
      end
    end
    local commit_keys = rawget(keys, 'commit')
    if commit_keys ~= nil then
      vim.validate('forge.keys.commit', commit_keys, 'table')
      for _, k in ipairs({ 'review', 'browse', 'yank', 'refresh' }) do
        vim.validate('forge.keys.commit.' .. k, commit_keys[k], key_or_false, 'string or false')
      end
    end
    local worktree_keys = rawget(keys, 'worktree')
    if worktree_keys ~= nil then
      vim.validate('forge.keys.worktree', worktree_keys, 'table')
      for _, k in ipairs({ 'add', 'delete', 'yank', 'refresh' }) do
        vim.validate('forge.keys.worktree.' .. k, worktree_keys[k], key_or_false, 'string or false')
      end
    end
    if keys.log ~= nil then
      vim.validate('forge.keys.log', keys.log, 'table')
      for _, k in ipairs({
        'close',
        'next_step',
        'prev_step',
        'next_error',
        'prev_error',
        'browse',
        'refresh',
      }) do
        vim.validate('forge.keys.log.' .. k, keys.log[k], key_or_false, 'string or false')
      end
    end
  end

  for name, source in pairs(cfg.sources) do
    vim.validate('forge.sources.' .. name, source, 'table')
    if source.hosts ~= nil then
      vim.validate('forge.sources.' .. name .. '.hosts', source.hosts, 'table')
    end
  end

  for name, enabled in pairs(cfg.contexts) do
    vim.validate('forge.contexts.' .. name, enabled, 'boolean')
  end

  for name, enabled in pairs(cfg.sections) do
    vim.validate('forge.sections.' .. name, enabled, 'boolean')
  end

  for name, route in pairs(cfg.routes) do
    vim.validate('forge.routes.' .. name, route, 'string')
  end

  if type(cfg.keys) == 'table' then
    local pr_keys = rawget(cfg.keys, 'pr')
    local user_keys = type(user.keys) == 'table' and user.keys or nil
    local user_pr_keys = type(user_keys) == 'table' and rawget(user_keys, 'pr') or nil
    if type(pr_keys) == 'table' then
      if type(user_pr_keys) == 'table' and user_pr_keys.review ~= nil then
        pr_keys.review = user_pr_keys.review
      elseif type(user_pr_keys) == 'table' and user_pr_keys.diff ~= nil then
        pr_keys.review = user_pr_keys.diff
      elseif pr_keys.review == nil then
        pr_keys.review = pr_keys.diff
      end
      pr_keys.diff = pr_keys.review
    end
  end

  return cfg
end

M.setup_highlights()

return M
