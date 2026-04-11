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
---@field back string|false?
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
---@field filter_prev string|false
---@field refresh string|false

---@class forge.IssuePickerKeys
---@field browse string|false
---@field close string|false
---@field create string|false
---@field filter string|false
---@field filter_prev string|false
---@field refresh string|false

---@class forge.CIPickerKeys
---@field log string|false
---@field watch string|false
---@field browse string|false
---@field filter string|false
---@field filter_prev string|false
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
---@field filter_prev string|false
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
---@field commits integer
---@field runs integer
---@field releases integer

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
    back = '<c-o>',
    pr = {
      review = '<c-d>',
      diff = '<c-d>',
      worktree = '<c-w>',
      ci = '<c-t>',
      browse = '<c-x>',
      create = '<c-a>',
      filter = '<tab>',
      refresh = '<c-r>',
    },
    issue = {
      browse = '<c-x>',
      close = '<c-s>',
      filter = '<tab>',
      refresh = '<c-r>',
      create = '<c-a>',
    },
    ci = {
      log = '<cr>',
      watch = '<c-w>',
      browse = '<c-x>',
      filter = '<tab>',
      refresh = '<c-r>',
    },
    release = {
      browse = '<cr>',
      yank = '<c-y>',
      delete = '<c-d>',
      filter = '<tab>',
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
      open = 'o',
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
      commits = 100,
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
  ForgeComposeFile = 'Directory',
  ForgeComposeAdded = 'Added',
  ForgeComposeRemoved = 'Removed',
  ForgeComposeHeader = 'PreProc',
  ForgeComposeLabel = 'Label',
  ForgeNumber = 'Number',
  ForgeOpen = 'DiagnosticOk',
  ForgeMerged = 'Special',
  ForgeClosed = 'Comment',
  ForgePass = 'DiagnosticOk',
  ForgeFail = 'DiagnosticError',
  ForgePending = 'DiagnosticWarn',
  ForgeSkip = 'Comment',
  ForgeBranch = 'Special',
  ForgeBranchCurrent = function()
    local hl = vim.api.nvim_get_hl(0, { name = 'Special', link = false })
    return vim.tbl_extend('force', hl, { bold = true })
  end,
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
    elseif type(val) == 'function' then
      vim.api.nvim_set_hl(0, group, vim.tbl_extend('keep', { default = true }, val()))
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
  vim.validate('forge.display.limits.commits', cfg.display.limits.commits, 'number')
  vim.validate('forge.display.limits.runs', cfg.display.limits.runs, 'number')
  vim.validate('forge.display.limits.releases', cfg.display.limits.releases, 'number')

  local key_or_false = function(v)
    return v == nil or v == false or type(v) == 'string'
  end
  if type(cfg.keys) == 'table' then
    local keys = cfg.keys --[[@as forge.KeysConfig]]
    vim.validate('forge.keys.back', keys.back, key_or_false, 'string or false')
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
        'filter_prev',
        'refresh',
      }) do
        vim.validate('forge.keys.pr.' .. k, keys.pr[k], key_or_false, 'string or false')
      end
    end
    if keys.issue ~= nil then
      vim.validate('forge.keys.issue', keys.issue, 'table')
      for _, k in ipairs({ 'browse', 'close', 'create', 'filter', 'filter_prev', 'refresh' }) do
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
        'filter_prev',
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
      for _, k in ipairs({ 'browse', 'yank', 'delete', 'filter', 'filter_prev', 'refresh' }) do
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
